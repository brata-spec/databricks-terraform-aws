region = "us-east-1"

# One metastore per region per account: us-east-1 already has one, so attach to it.
# Everything INSIDE it for this repo is new (credential, location, catalogs, owners).
metastore = {
  create = false
  name   = "metastore-us-east-1"
}

# New platform admin group: owns this repo's UC objects, ADMIN on every workspace.
# The new deployer service principal is added to it.
platform_admin_group        = "dbxp-platform-admins"
create_platform_admin_group = true
manage_deployer_membership  = true

# New team groups (no SCIM in this account)
account_groups = [
  "dbxp-de-admins",
  "dbxp-de-engineers",
  "dbxp-de-analysts",
]

# dbxp account level: first deploy
