region = "us-east-1"

# Client already has a Databricks account: if a metastore exists in this region,
# set create = false and give its exact name. Otherwise create = true.
metastore = {
  create = false
  name   = "<existing-metastore-name>"
}

platform_admin_group       = "dbr-platform-admins"
manage_deployer_membership = true

# Create team groups here only if they are NOT synced from the IdP (SCIM).
# A group created here and also pushed by SCIM will conflict.
account_groups = [
  # "dbr-de-engineers", "dbr-de-analysts",
  # "dbr-ds-engineers", "dbr-ds-analysts",
  # "dbr-elections-engineers", "dbr-elections-analysts",
]
