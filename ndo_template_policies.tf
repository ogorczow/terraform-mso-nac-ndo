locals {
  template_policy = flatten(distinct([
    for template in try(local.template_policies, []) : template.tenant
  ]))
}

data "mso_rest" "template_policies" {
  path = "api/v1/templates/list-identity"
}

data "mso_tenant" "template_policy" {
  for_each = toset([for template_policy in local.template_policies : template_policy if !var.manage_tenants && var.manage_schemas])
  name     = each.value
}

resource "mso_template" "template_policy" {
  for_each = { for template_policy in try(local.template_policies, []) : template_policy.name => template_policy }
  template_name     = each.value.name
  template_type     = each.value.type
  tenant_id         = var.manage_tenants ? mso_tenant.tenant[each.value.tenant].id : data.mso_tenant.template_tenant[each.value.tenant].id

  depends_on = [
    mso_schema.schema,
    mso_tenant.tenant
  ]
}

locals {
  dhcp_relay_policies = flatten([
    for template_policy in local.template_policies : [
      for dhcp_relay_policy in try(template_policy.dhcp_relay_policies, []) : {
          key = "${template_policy.name}/${dhcp_relay_policy.name}"
          template_id = mso_template.template_policy[template_policy.name].id
          name = dhcp_relay_policy.name
          descr = dhcp_relay_policy.description
          dhcp_relay_providers = [for dhcp_relay_provider in try(dhcp_relay_policy.dhcp_relay_providers, []): {
            type = try(contains(["l3out", "epg"], dhcp_relay_provider.type), false) ? dhcp_relay_provider.type : local.defaults.ndo.template_policies.dhcp_relay_policies.dhcp_relay_providers.type
            dhcp_server_address = dhcp_relay_provider.ip
            template = dhcp_relay_provider.template
            tenant   = dhcp_relay_provider.tenant
            schema   = dhcp_relay_provider.schema
            application_epg = dhcp_relay_provider.epg
            external_epg = dhcp_relay_provider.epg
            dhcp_server_vrf_preference = try(dhcp_relay_provider.vrf_preference, local.defaults.ndo.template_policies.dhcp_relay_policies.dhcp_relay_providers.vrf_preference)
          }]
        }
      ] if template_policy.type == "tenant"])
}

resource "mso_tenant_policies_dhcp_relay_policy" "dhcp_relay_policy" {
  for_each = { for dhcp_relay_policy in local.dhcp_relay_policies : dhcp_relay_policy.key => dhcp_relay_policy }
  template_id = each.value.template_id
  name = each.value.name
  description = each.value.descr

  dhcp_relay_providers {
    dhcp_server_address = "5.5.5.5"
    application_epg_uuid = "67e9ca85-5737-42c9-a2c1-743e691e7925" #dhcp_relay_providers.value.type == "epg" ?  : null 
  }
  dynamic "dhcp_relay_providers" {
    for_each = { for dhcp_relay_provider in try(each.value.dhcp_relay_providers, []) : dhcp_relay_provider.dhcp_server_address => dhcp_relay_provider }
    content {
      dhcp_server_address = dhcp_relay_providers.value.dhcp_server_address
      application_epg_uuid = dhcp_relay_providers.value.type == "epg" ?  dhcp_relay_providers.value.epg : null
      #external_epg_uuid = dhcp_relay_providers.value.type == "l3out" ? mso_schema_site_anp_epg. dhcp_relay_providers.value.external_epg : null
      dhcp_server_vrf_preference = dhcp_relay_providers.value.dhcp_server_vrf_preference
    }
  }
}