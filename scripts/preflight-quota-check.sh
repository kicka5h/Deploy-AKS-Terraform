#!/usr/bin/env bash
# Pre-flight quota and capacity validation
# Parses a Terraform plan JSON to extract planned resources,
# then checks Azure quotas to ensure sufficient capacity exists.
#
# Usage: ./scripts/preflight-quota-check.sh <plan-json-file> <tfvars-file>
# Exit code 0 = pass, 1 = fail

set -euo pipefail

PLAN_JSON="$1"
TFVARS_FILE="$2"
REPORT_FILE="${3:-quota_report.md}"

# --- Helpers ---

log()  { echo "[preflight] $*"; }
warn() { echo "::warning::$*"; }
fail() { echo "::error::$*"; FAILED=1; }

FAILED=0

# --- Parse tfvars for key values ---

parse_tfvar() {
  local key="$1"
  local default="$2"
  grep -E "^\s*${key}\s*=" "$TFVARS_FILE" 2>/dev/null \
    | head -1 \
    | sed 's/.*=\s*"\?\([^"]*\)"\?.*/\1/' \
    | tr -d '[:space:]' || echo "$default"
}

LOCATION=$(parse_tfvar "location" "westus")
DR_LOCATION=$(parse_tfvar "dr_location" "eastus")
ENABLE_DR=$(parse_tfvar "enable_dr" "false")
VM_SIZE=$(parse_tfvar "aks_vm_size" "Standard_D2_v2")
DR_VM_SIZE=$(parse_tfvar "dr_aks_vm_size" "Standard_D2_v2")
NODE_COUNT=$(parse_tfvar "aks_node_count" "1")
DR_NODE_COUNT=$(parse_tfvar "dr_aks_node_count" "0")
AUTO_SCALING=$(parse_tfvar "aks_auto_scaling_enabled" "false")
MAX_COUNT=$(parse_tfvar "aks_auto_scaling_max_count" "0")

# --- Parse Terraform plan JSON ---

log "Parsing terraform plan JSON..."

RESOURCES_TO_CREATE=$(jq '[.resource_changes[]? | select(.change.actions[] == "create")] | length' "$PLAN_JSON" 2>/dev/null || echo "0")
RESOURCES_TO_UPDATE=$(jq '[.resource_changes[]? | select(.change.actions[] == "update")] | length' "$PLAN_JSON" 2>/dev/null || echo "0")
RESOURCES_TO_DELETE=$(jq '[.resource_changes[]? | select(.change.actions[] == "delete")] | length' "$PLAN_JSON" 2>/dev/null || echo "0")

# Extract planned AKS clusters
AKS_CLUSTERS=$(jq -r '[.resource_changes[]? | select(.type == "azurerm_kubernetes_cluster" and (.change.actions[] == "create"))] | length' "$PLAN_JSON" 2>/dev/null || echo "0")

# Extract planned VNets
VNET_COUNT=$(jq -r '[.resource_changes[]? | select(.type == "azurerm_virtual_network" and (.change.actions[] == "create"))] | length' "$PLAN_JSON" 2>/dev/null || echo "0")

# Extract planned public IPs (from LBs, Front Door, etc.)
PUBLIC_IP_COUNT=$(jq -r '[.resource_changes[]? | select(.type == "azurerm_public_ip" and (.change.actions[] == "create"))] | length' "$PLAN_JSON" 2>/dev/null || echo "0")

# Extract planned Front Door profiles
FRONTDOOR_COUNT=$(jq -r '[.resource_changes[]? | select(.type == "azurerm_cdn_frontdoor_profile" and (.change.actions[] == "create"))] | length' "$PLAN_JSON" 2>/dev/null || echo "0")

# Extract planned load balancers
LB_COUNT=$(jq -r '[.resource_changes[]? | select((.type == "azurerm_lb" or .type == "azurerm_kubernetes_cluster") and (.change.actions[] == "create"))] | length' "$PLAN_JSON" 2>/dev/null || echo "0")

log "Plan summary: +${RESOURCES_TO_CREATE} ~${RESOURCES_TO_UPDATE} -${RESOURCES_TO_DELETE}"
log "AKS clusters to create: $AKS_CLUSTERS"
log "VNets to create: $VNET_COUNT"

# --- Calculate vCPU requirements ---

# Map common VM sizes to vCPU counts
get_vcpu_count() {
  local size="$1"
  case "$size" in
    Standard_B2s)    echo 2 ;;
    Standard_D2_v2)  echo 2 ;;
    Standard_D2_v3)  echo 2 ;;
    Standard_D2s_v3) echo 2 ;;
    Standard_D4_v2)  echo 8 ;;
    Standard_D4_v3)  echo 4 ;;
    Standard_D4s_v3) echo 4 ;;
    Standard_D8_v3)  echo 8 ;;
    Standard_D8s_v3) echo 8 ;;
    Standard_D16_v3) echo 16 ;;
    Standard_E2_v3)  echo 2 ;;
    Standard_E4_v3)  echo 4 ;;
    Standard_F2s_v2) echo 2 ;;
    Standard_F4s_v2) echo 4 ;;
    *)
      # Try to get from Azure API
      local count
      count=$(az vm list-sizes --location "$LOCATION" \
        --query "[?name=='${size}'].numberOfCores | [0]" -o tsv 2>/dev/null || echo "0")
      echo "${count:-0}"
      ;;
  esac
}

PRIMARY_VCPUS=$(get_vcpu_count "$VM_SIZE")
PRIMARY_TOTAL_VCPUS=$((PRIMARY_VCPUS * NODE_COUNT))

if [ "$AUTO_SCALING" = "true" ] && [ "$MAX_COUNT" != "null" ] && [ "$MAX_COUNT" != "0" ]; then
  PRIMARY_MAX_VCPUS=$((PRIMARY_VCPUS * MAX_COUNT))
  log "Primary cluster: $NODE_COUNT-$MAX_COUNT nodes x $PRIMARY_VCPUS vCPUs = $PRIMARY_TOTAL_VCPUS-$PRIMARY_MAX_VCPUS vCPUs"
else
  PRIMARY_MAX_VCPUS=$PRIMARY_TOTAL_VCPUS
  log "Primary cluster: $NODE_COUNT nodes x $PRIMARY_VCPUS vCPUs = $PRIMARY_TOTAL_VCPUS vCPUs"
fi

DR_TOTAL_VCPUS=0
DR_MAX_VCPUS=0
if [ "$ENABLE_DR" = "true" ]; then
  DR_VCPUS=$(get_vcpu_count "$DR_VM_SIZE")
  DR_TOTAL_VCPUS=$((DR_VCPUS * DR_NODE_COUNT))
  DR_MAX_VCPUS=$DR_TOTAL_VCPUS
  log "DR cluster: $DR_NODE_COUNT nodes x $DR_VCPUS vCPUs = $DR_TOTAL_VCPUS vCPUs"
fi

TOTAL_VCPUS_NEEDED=$((PRIMARY_MAX_VCPUS + DR_MAX_VCPUS))
log "Total vCPUs needed (worst case): $TOTAL_VCPUS_NEEDED"

# --- Check Azure quotas ---

check_quota() {
  local location="$1"
  local label="$2"

  log "Checking quotas in $location ($label)..."

  # Regional vCPU quota
  local total_cores_usage
  total_cores_usage=$(az vm list-usage --location "$location" \
    --query "[?name.value=='cores'].{used:currentValue, limit:limit}" -o json 2>/dev/null || echo "[]")

  local cores_used cores_limit cores_available
  cores_used=$(echo "$total_cores_usage" | jq '.[0].used // 0')
  cores_limit=$(echo "$total_cores_usage" | jq '.[0].limit // 0')
  cores_available=$((cores_limit - cores_used))

  echo "  Regional vCPUs: ${cores_used}/${cores_limit} used (${cores_available} available)"

  # VM family quota
  local family
  family=$(echo "$VM_SIZE" | sed -E 's/Standard_([A-Za-z]+)[0-9].*/\1/' | tr '[:upper:]' '[:lower:]')
  local family_filter="standard${family}Family"

  local family_usage
  family_usage=$(az vm list-usage --location "$location" \
    --query "[?name.value=='${family_filter}'].{used:currentValue, limit:limit}" -o json 2>/dev/null || echo "[]")

  local family_used family_limit family_available
  family_used=$(echo "$family_usage" | jq '.[0].used // 0')
  family_limit=$(echo "$family_usage" | jq '.[0].limit // 0')
  family_available=$((family_limit - family_used))

  echo "  ${family_filter}: ${family_used}/${family_limit} used (${family_available} available)"

  # Network quotas
  local net_usage
  net_usage=$(az network list-usages --location "$location" \
    --query "[?contains(name.value, 'VirtualNetworks') || contains(name.value, 'PublicIPAddresses') || contains(name.value, 'LoadBalancers') || contains(name.value, 'NetworkSecurityGroups')].{name:name.localizedValue, used:currentValue, limit:limit}" \
    -o json 2>/dev/null || echo "[]")

  echo "  Network quotas:"
  echo "$net_usage" | jq -r '.[] | "    \(.name): \(.used)/\(.limit)"' 2>/dev/null || echo "    Could not retrieve"

  # Return available cores for validation
  echo "$cores_available"
}

# --- Begin report ---

{
  echo "# Pre-flight Quota Validation Report"
  echo ""
  echo "## Planned Changes"
  echo "| Metric | Count |"
  echo "|--------|-------|"
  echo "| Resources to create | $RESOURCES_TO_CREATE |"
  echo "| Resources to update | $RESOURCES_TO_UPDATE |"
  echo "| Resources to delete | $RESOURCES_TO_DELETE |"
  echo "| AKS clusters | $AKS_CLUSTERS |"
  echo "| Virtual networks | $VNET_COUNT |"
  echo "| Front Door profiles | $FRONTDOOR_COUNT |"
  echo ""
  echo "## Compute Requirements"
  echo "| Cluster | VM Size | Nodes | vCPUs/Node | Total vCPUs |"
  echo "|---------|---------|-------|------------|-------------|"
  echo "| Primary | $VM_SIZE | $NODE_COUNT | $PRIMARY_VCPUS | $PRIMARY_TOTAL_VCPUS |"
  if [ "$ENABLE_DR" = "true" ]; then
    echo "| DR | $DR_VM_SIZE | $DR_NODE_COUNT | $DR_VCPUS | $DR_TOTAL_VCPUS |"
  fi
  echo "| **Total (max)** | | | | **$TOTAL_VCPUS_NEEDED** |"
  echo ""
} > "$REPORT_FILE"

# --- Primary region checks ---

{
  echo "## Primary Region: $LOCATION"
  echo '```'
} >> "$REPORT_FILE"

PRIMARY_AVAILABLE=$(check_quota "$LOCATION" "primary" | tee -a "$REPORT_FILE" | tail -1)

{
  echo '```'
  echo ""
} >> "$REPORT_FILE"

# Validate primary region capacity
if [ "$PRIMARY_AVAILABLE" -lt "$PRIMARY_MAX_VCPUS" ] 2>/dev/null; then
  fail "INSUFFICIENT QUOTA in $LOCATION: need $PRIMARY_MAX_VCPUS vCPUs but only $PRIMARY_AVAILABLE available"
  echo "> **FAIL**: Need $PRIMARY_MAX_VCPUS vCPUs, only $PRIMARY_AVAILABLE available" >> "$REPORT_FILE"
else
  log "PRIMARY OK: $PRIMARY_AVAILABLE vCPUs available >= $PRIMARY_MAX_VCPUS needed"
  echo "> **PASS**: $PRIMARY_AVAILABLE vCPUs available >= $PRIMARY_MAX_VCPUS needed" >> "$REPORT_FILE"
fi
echo "" >> "$REPORT_FILE"

# --- DR region checks ---

if [ "$ENABLE_DR" = "true" ]; then
  {
    echo "## DR Region: $DR_LOCATION"
    echo '```'
  } >> "$REPORT_FILE"

  DR_AVAILABLE=$(check_quota "$DR_LOCATION" "DR" | tee -a "$REPORT_FILE" | tail -1)

  {
    echo '```'
    echo ""
  } >> "$REPORT_FILE"

  if [ "$DR_AVAILABLE" -lt "$DR_MAX_VCPUS" ] 2>/dev/null; then
    fail "INSUFFICIENT QUOTA in $DR_LOCATION: need $DR_MAX_VCPUS vCPUs but only $DR_AVAILABLE available"
    echo "> **FAIL**: Need $DR_MAX_VCPUS vCPUs, only $DR_AVAILABLE available" >> "$REPORT_FILE"
  else
    log "DR OK: $DR_AVAILABLE vCPUs available >= $DR_MAX_VCPUS needed"
    echo "> **PASS**: $DR_AVAILABLE vCPUs available >= $DR_MAX_VCPUS needed" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
fi

# --- Resource provider availability ---

{
  echo "## Resource Provider Availability"
  echo '```'
} >> "$REPORT_FILE"

log "Checking resource provider registration..."
REQUIRED_PROVIDERS=("Microsoft.ContainerService" "Microsoft.Network" "Microsoft.ContainerRegistry" "Microsoft.Cdn")

for provider in "${REQUIRED_PROVIDERS[@]}"; do
  STATE=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
  echo "  $provider: $STATE" | tee -a "$REPORT_FILE"
  if [ "$STATE" != "Registered" ]; then
    fail "Resource provider $provider is not registered (state: $STATE)"
  fi
done

{
  echo '```'
  echo ""
} >> "$REPORT_FILE"

# --- VM size availability ---

{
  echo "## VM Size Availability"
} >> "$REPORT_FILE"

log "Checking VM size availability..."

check_vm_availability() {
  local location="$1"
  local vm_size="$2"

  local restrictions
  restrictions=$(az vm list-skus --location "$location" --size "$vm_size" \
    --query "[0].restrictions[?type=='Location'].reasonCode | [0]" -o tsv 2>/dev/null || echo "Unknown")

  if [ -z "$restrictions" ] || [ "$restrictions" = "null" ] || [ "$restrictions" = "None" ]; then
    echo "  $vm_size in $location: Available" | tee -a "$REPORT_FILE"
  else
    echo "  $vm_size in $location: RESTRICTED ($restrictions)" | tee -a "$REPORT_FILE"
    fail "$vm_size is not available in $location: $restrictions"
  fi
}

echo '```' >> "$REPORT_FILE"
check_vm_availability "$LOCATION" "$VM_SIZE"
if [ "$ENABLE_DR" = "true" ]; then
  check_vm_availability "$DR_LOCATION" "$DR_VM_SIZE"
fi
{
  echo '```'
  echo ""
} >> "$REPORT_FILE"

# --- Final result ---

echo "" >> "$REPORT_FILE"
if [ "$FAILED" -eq 0 ]; then
  echo "## Result: PASS" >> "$REPORT_FILE"
  log "Pre-flight validation PASSED"
else
  echo "## Result: FAIL" >> "$REPORT_FILE"
  log "Pre-flight validation FAILED"
fi

cat "$REPORT_FILE"
exit "$FAILED"
