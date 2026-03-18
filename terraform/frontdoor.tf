# Azure Front Door with WAF and failover routing
# Only created when DR is enabled

# Front Door Profile
resource "azurerm_cdn_frontdoor_profile" "main" {
  count               = var.enable_dr ? 1 : 0
  name                = "${var.env}-frontdoor"
  resource_group_name = azurerm_resource_group.frontdoor[0].name
  sku_name            = var.frontdoor_sku
  tags                = var.tags
}

# Front Door Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  count                    = var.enable_dr ? 1 : 0
  name                     = "${var.env}-kube-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main[0].id
  tags                     = var.tags
}

# Origin Group with health probes and failover
resource "azurerm_cdn_frontdoor_origin_group" "aks" {
  count                                                    = var.enable_dr ? 1 : 0
  name                                                     = "${var.env}-aks-origin-group"
  cdn_frontdoor_profile_id                                 = azurerm_cdn_frontdoor_profile.main[0].id
  session_affinity_enabled                                 = false
  restore_traffic_time_to_healed_or_new_endpoint_in_minutes = 5

  health_probe {
    interval_in_seconds = 30
    path                = "/healthz"
    protocol            = "Https"
    request_type        = "HEAD"
  }

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
}

# Origin - Primary AKS (priority 1)
resource "azurerm_cdn_frontdoor_origin" "primary" {
  count                          = var.enable_dr ? 1 : 0
  name                           = "${var.env}-primary-origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.aks[0].id
  enabled                        = true
  host_name                      = azurerm_kubernetes_cluster.aks.kube_config[0].host
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_kubernetes_cluster.aks.kube_config[0].host
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

# Origin - DR AKS (priority 2 - failover)
resource "azurerm_cdn_frontdoor_origin" "dr" {
  count                          = var.enable_dr ? 1 : 0
  name                           = "${var.env}-dr-origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.aks[0].id
  enabled                        = true
  host_name                      = azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].host
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].host
  priority                       = 2
  weight                         = 1000
  certificate_name_check_enabled = true
}

# Route
resource "azurerm_cdn_frontdoor_route" "default" {
  count                         = var.enable_dr ? 1 : 0
  name                          = "${var.env}-default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main[0].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.aks[0].id
  cdn_frontdoor_origin_ids      = [
    azurerm_cdn_frontdoor_origin.primary[0].id,
    azurerm_cdn_frontdoor_origin.dr[0].id
  ]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = [
      "text/html",
      "text/css",
      "text/javascript",
      "application/javascript",
      "application/json",
      "application/xml",
      "text/plain",
      "image/svg+xml",
      "application/font-woff",
      "application/font-woff2",
    ]
  }

  cdn_frontdoor_rule_set_ids = [azurerm_cdn_frontdoor_rule_set.security_headers[0].id]
}

# --- WAF Policy ---
resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  count                             = var.enable_dr ? 1 : 0
  name                              = "${var.env}kubewaf"
  resource_group_name               = azurerm_resource_group.frontdoor[0].name
  sku_name                          = var.frontdoor_sku
  enabled                           = true
  mode                              = var.frontdoor_waf_mode
  redirect_url                      = null
  custom_block_response_status_code = 403
  custom_block_response_body        = base64encode("Blocked by WAF policy.")

  # OWASP managed rule set
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  # Bot protection managed rule set
  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.1"
    action  = "Block"
  }

  # Rate limiting rule
  custom_rule {
    name     = "RateLimitRule"
    enabled  = true
    priority = 100
    type     = "RateLimitRule"
    action   = "Block"

    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 1000

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = true
      match_values       = ["127.0.0.1"]
    }
  }

  # Geo-blocking: block all countries except US
  custom_rule {
    name     = "GeoBlockNonUS"
    enabled  = true
    priority = 50
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "SocketAddr"
      operator           = "GeoMatch"
      negation_condition = true
      match_values       = ["US"]
    }
  }

  # Block suspicious request tooling
  custom_rule {
    name     = "BlockSuspiciousRequests"
    enabled  = true
    priority = 200
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "RequestHeader"
      selector           = "User-Agent"
      operator           = "Contains"
      negation_condition = false
      match_values       = ["scanner", "nikto", "sqlmap"]
      transforms         = ["Lowercase"]
    }
  }

  tags = var.tags
}

# Associate WAF policy with Front Door security policy
resource "azurerm_cdn_frontdoor_security_policy" "waf" {
  count                    = var.enable_dr ? 1 : 0
  name                     = "${var.env}-waf-security-policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main[0].id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.waf[0].id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.main[0].id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

# --- Security Headers Rule Set ---
resource "azurerm_cdn_frontdoor_rule_set" "security_headers" {
  count                    = var.enable_dr ? 1 : 0
  name                     = "${var.env}securityheaders"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main[0].id
}

resource "azurerm_cdn_frontdoor_rule" "add_security_headers" {
  count                     = var.enable_dr ? 1 : 0
  name                      = "AddSecurityHeaders"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.security_headers[0].id
  order                     = 1

  actions {
    response_header_action {
      header_action = "Overwrite"
      header_name   = "Strict-Transport-Security"
      value         = "max-age=31536000; includeSubDomains; preload"
    }
    response_header_action {
      header_action = "Overwrite"
      header_name   = "X-Content-Type-Options"
      value         = "nosniff"
    }
    response_header_action {
      header_action = "Overwrite"
      header_name   = "X-Frame-Options"
      value         = "SAMEORIGIN"
    }
    response_header_action {
      header_action = "Overwrite"
      header_name   = "X-XSS-Protection"
      value         = "1; mode=block"
    }
    response_header_action {
      header_action = "Overwrite"
      header_name   = "Referrer-Policy"
      value         = "strict-origin-when-cross-origin"
    }
  }
}
