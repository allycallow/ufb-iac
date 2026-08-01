workspace := env_var_or_default("TF_WORKSPACE", "default")

# List available recipes
default:
    @just --list

# Format all .tf files recursively
fmt:
    terraform fmt -recursive

# Check formatting without writing changes
fmt-check:
    terraform fmt -check -recursive -diff

# Initialize (or re-init) the working directory
init:
    terraform init

# Validate the configuration
validate: fmt-check
    terraform validate

# Select or create a workspace
workspace-select ws=workspace:
    terraform workspace select -or-create {{ws}}

# Show an execution plan for the given workspace
plan ws=workspace: (workspace-select ws)
    terraform plan

# Apply changes for the given workspace
apply ws=workspace: (workspace-select ws)
    terraform apply

# Destroy resources for the given workspace
destroy ws=workspace: (workspace-select ws)
    terraform destroy

# Show current state for the given workspace
show ws=workspace: (workspace-select ws)
    terraform show

# List all workspaces
workspaces:
    terraform workspace list
