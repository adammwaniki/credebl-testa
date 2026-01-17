#!/bin/bash

set -euo pipefail

# Constants
LOG_FILE="deployment.log"
KEYCLOAK_VERSION="25.0.6"
TERRAFORM_DIR="../../terraform-script/keycloak/"
DOCKER_COMPOSE_FILE="docker-compose.yml"
ROOT_DIR="../../local-deployment/platform/"
MASTER_TABLE_FILE="$PWD/platform/libs/prisma-service/prisma/data/credebl-master-table/"

# Initialize logging
exec > >(tee -a "${LOG_FILE}") 2>&1
echo -e "\n\n=== Deployment started at $(date) ==="

# Cross-platform sed in-place function
sed_inplace() {
    if [ "$(uname)" == "Darwin" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    local symbol=""
    
    case "$color" in
        "green") symbol="✅" ;;
        "yellow") symbol="📁" ;;
        "red") symbol="❌" ;;
        "blue") symbol="🔍" ;;
        "purple") symbol="🛡️" ;;
        "blue") symbol="🔵" ;;
        *) symbol="📌" ;;
    esac
    
    echo -e "${symbol} ${message}"
}

# Function to check command existence
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

prompt_yes_no() {
  local prompt_message=$1
  local response

  while true; do
    read -p "$prompt_message (yes/no): " response
    case "$response" in
      yes|y) return 0 ;;
      no|n) return 1 ;;
      *) echo "Please enter only 'yes' or 'no'." ;;
    esac
  done
}

# Step 1: Clone repository
clone_platform(){
    print_message "blue" "\n Setting up CREDEBL Platform..."
    
    read -p "Provide branch name you want to work on: " BRANCH
    echo "You entered branch: $BRANCH"

    if [ -d "platform" ]; then
        print_message "yellow" "Platform directory exists, pulling latest changes..."
        cd platform && git fetch origin && git checkout $BRANCH && git pull origin $BRANCH
    else
        git clone -b main https://github.com/credebl/platform.git || {
            print_message "red" "Failed to clone Studio repository"
            exit 1
        }
        cd platform && git checkout $BRANCH && git pull origin $BRANCH
    fi
}

# Step 2: Prepare env file and Check  ports availability
prepare_env_file(){
    if [ ! -f .env ]; then
    print_message "yellow" "Copying .env.demo to .env..."
    cp .env.demo .env || {
        print_message "red" "Failed to copy .env.demo to .env"
        exit 1
    }
    else
        print_message "green" ".env already exists. Skipping copy and checking existing values..."
    fi
}

PORTS_POSTGRES=5432
PORTS_API_GATEWAY=5000
PORTS_REDIS=6379
PORTS_KEYCLOAK=8080
PORTS_SCHEMA_FILE_SERVER=4000
PORTS_STUDIO=3000

# Function to check if port is available
is_port_available() {
    local port=$1
    
    # Method 1: Try netcat first (most reliable)
    if command -v nc &>/dev/null; then
        if nc -z 127.0.0.1 "$port" &>/dev/null; then
            return 1 # Port is in use
        else
            return 0 # Port is available
        fi
    fi
    
    # Method 2: macOS fallback using lsof
    if [[ "$OSTYPE" == "darwin"* ]] && command -v lsof &>/dev/null; then
        if lsof -i :"$port" -sTCP:LISTEN &>/dev/null; then
            return 1
        else
            return 0
        fi
    fi
    
    # Method 3: Linux /dev/tcp check (bash builtin)
    if (echo >/dev/tcp/127.0.0.1/"$port") &>/dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

# Function to find first available port from list
find_available_port() {
    local base_port=$1
    local max_attempts=10
    local current_port=$base_port
    
    for (( i=0; i<max_attempts; i++ )); do
        if is_port_available "$current_port"; then
            echo "$current_port"
            return 0
        fi
        ((current_port++))
    done
    
    print_message "red" "Could not find available port after $max_attempts attempts (base: $base_port)"
    exit 1
}

# Check and assign ports
configure_ports() {
    USED_PORT_POSTGRES=$(find_available_port "$PORTS_POSTGRES")
    USED_PORT_API_GATEWAY=$(find_available_port "$PORTS_API_GATEWAY")
    USED_PORT_REDIS=$(find_available_port "$PORTS_REDIS")
    USED_PORT_KEYCLOAK=$(find_available_port "$PORTS_KEYCLOAK")
    USED_PORT_SCHEMA_FILE_SERVER=$(find_available_port "$PORTS_SCHEMA_FILE_SERVER")
    USED_PORT_STUDIO=$(find_available_port "$PORTS_STUDIO")
    
    echo "Assigned ports:"
    echo "PostgreSQL: $USED_PORT_POSTGRES"
    echo "API Gateway: $USED_PORT_API_GATEWAY"
    echo "Redis: $USED_PORT_REDIS"
    echo "Keycloak: $USED_PORT_KEYCLOAK"
    echo "Schema Server: $USED_PORT_SCHEMA_FILE_SERVER"
    echo "Studio: $USED_PORT_STUDIO"
    
    update_ports_config
}

update_ports_config() {
    sed_inplace "
        s|^PUBLIC_LOCALHOST_URL=.*|PUBLIC_LOCALHOST_URL=http://localhost:${USED_PORT_API_GATEWAY}|;
        s|^SOCKET_HOST=.*|SOCKET_HOST=ws://your-ip:${USED_PORT_API_GATEWAY}|;
        s|^UPLOAD_LOGO_HOST=.*|UPLOAD_LOGO_HOST=your-ip:${USED_PORT_API_GATEWAY}|;
        s|^API_ENDPOINT=.*|API_ENDPOINT=your-ip:${USED_PORT_API_GATEWAY}|;
        s|^API_GATEWAY_PORT=.*|API_GATEWAY_PORT=${USED_PORT_API_GATEWAY}|;
        s|^REDIS_PORT=.*|REDIS_PORT=${USED_PORT_REDIS}|;
        s|^APP_PORT=.*|APP_PORT=${USED_PORT_SCHEMA_FILE_SERVER}|;
        s|^SCHEMA_FILE_SERVER_URL=.*|SCHEMA_FILE_SERVER_URL=http://your-ip:${USED_PORT_SCHEMA_FILE_SERVER}/schemas/|;
        s|^WALLET_STORAGE_PORT=.*|WALLET_STORAGE_PORT=${USED_PORT_POSTGRES}|;
        s|^POOL_DATABASE_URL=.*|POOL_DATABASE_URL=postgresql://postgres:postgres@your-ip:${USED_PORT_POSTGRES}/credebl|;
        s|^DATABASE_URL=.*|DATABASE_URL=postgresql://postgres:postgres@your-ip:${USED_PORT_POSTGRES}/credebl|;
    " .env
    sed_inplace "
        s|[0-9]*:6379|${USED_PORT_REDIS}:6379|;
    " docker-compose.redis.yml
    print_message "green" "Updated .env file and docker-compose available ports"
}

# Step 2: Prepare environment files

prepare_environment_variable() {
    print_message "yellow" "Preparing environment files..."
    postgres_setup=false
    escape_sed() {
    input="$1"
    printf '%s' "$input" | perl -pe 's/([&|\\])/\\$1/g'
}

    handle_existing_value() {
        local var_name=$1
        local prompt=$2
        local required=${3:-true}  # Default to true if not specified
        local current_value=$(grep "^$var_name=" .env | cut -d'=' -f2-)
        
        # Check for existing value
        if [[ -n "$current_value" ]]; then
            if [[ "$var_name" =~ (PASS|KEY) ]]; then
                # Don't show the actual value
                if prompt_yes_no "Found existing $var_name (hidden). Continue with this value?"; then
                    printf -v "$var_name" '%s' "$current_value"
                    print_message "green" "Using existing $var_name"
                    return
                else
                    print_message "yellow" "Will prompt for new $var_name value"
                fi
            else
                # Safe to display non-sensitive values
                if prompt_yes_no "Found existing $var_name=$current_value. Continue with this value?"; then
                    printf -v "$var_name" '%s' "$current_value"
                    print_message "green" "Using existing $var_name"
                    return
                else
                    print_message "yellow" "Will prompt for new $var_name value"
                fi
            fi
        fi
        
        # Input loop
        while true; do
            if [[ "$var_name" =~ (PASS|KEY) ]]; then
                read -rs -p "$prompt: " "$var_name"
                echo  # Move to a new line after silent input
            else
                read -r -p "$prompt: " "$var_name"
            fi
            if [ "$required" = "true" ] && [ -z "${!var_name}" ]; then
                print_message "red" "Value cannot be empty"
            else
                break
            fi
        done
    }


    # Collect required variables
    MACHINE_IP=$(ipconfig getifaddr en0 2>/dev/null || ip route get 1 | awk '{print $7; exit}')
    echo -e "\n Host IP fetched ${MACHINE_IP}"

    # Set default empty values for optional variables
    local AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-}
    local AWS_SECRET_KEY=${AWS_SECRET_KEY:-}
    local AWS_REGION=${AWS_REGION:-}
    local AWS_BUCKET=${AWS_BUCKET:-}
    local AWS_PUBLIC_ACCESS_KEY=${AWS_PUBLIC_ACCESS_KEY:-}
    local AWS_PUBLIC_SECRET_KEY=${AWS_PUBLIC_SECRET_KEY:-}
    local AWS_PUBLIC_REGION=${AWS_PUBLIC_REGION:-}
    local AWS_ORG_LOGO_BUCKET_NAME=${AWS_ORG_LOGO_BUCKET_NAME:-}
    local STUDIO_URL="http://${MACHINE_IP}:${USED_PORT_STUDIO}"

    handle_existing_value "SENDGRID_API_KEY" "Enter SendGrid API key"
    handle_existing_value "EMAIL_FROM" "Enter SendGrid sender email"

    # Required S3 variables
    echo -e "\n# Provide S3 credentials, required for storing connection URLs"
    handle_existing_value "AWS_S3_STOREOBJECT_ACCESS_KEY" "Enter AWS S3 Access Key"
    handle_existing_value "AWS_S3_STOREOBJECT_SECRET_KEY" "Enter AWS S3 Secret Key"
    handle_existing_value "AWS_S3_STOREOBJECT_REGION" "Enter AWS S3 Region"
    handle_existing_value "AWS_S3_STOREOBJECT_BUCKET" "Enter AWS S3 Bucket"

    # bulk issuance
    if prompt_yes_no "Do you want to use bulk issuance?"; then
        echo -e "\n# Provide S3 credentials for bulk issuance"
        handle_existing_value "AWS_ACCESS_KEY" "Enter AWS Access Key (bulk)"
        handle_existing_value "AWS_SECRET_KEY" "Enter AWS Secret Key (bulk)"
        handle_existing_value "AWS_REGION" "Enter AWS Region (bulk)"
        handle_existing_value "AWS_BUCKET" "Enter AWS Bucket (bulk)"
    fi

    # Optional org logos
    if prompt_yes_no "Do you want to upload org logos?"; then
        echo -e "\n# Provide S3 credentials for org logos"
        handle_existing_value "AWS_PUBLIC_ACCESS_KEY" "Enter AWS Public Access Key"
        handle_existing_value "AWS_PUBLIC_SECRET_KEY" "Enter AWS Public Secret Key"
        handle_existing_value "AWS_PUBLIC_REGION" "Enter AWS Public Region"
        handle_existing_value "AWS_ORG_LOGO_BUCKET_NAME" "Enter AWS Org Logo Bucket"
    fi

    sed_inplace "
        s|your-ip|$(escape_sed "$MACHINE_IP")|g;
        s|localhost|$(escape_sed "$MACHINE_IP")|g;
        s|^CREDEBL_DOMAIN=.*|CREDEBL_DOMAIN=$(escape_sed "$STUDIO_URL")|;
        s|^FRONT_END_URL=.*|FRONT_END_URL=$(escape_sed "$STUDIO_URL")|;
        s|^SENDGRID_API_KEY=.*|SENDGRID_API_KEY=$(escape_sed "$SENDGRID_API_KEY")|;
        /^# Used for storing connection URL/,/^$/ {
            s|^AWS_S3_STOREOBJECT_ACCESS_KEY=.*|AWS_S3_STOREOBJECT_ACCESS_KEY=$(escape_sed "$AWS_S3_STOREOBJECT_ACCESS_KEY")|;
            s|^AWS_S3_STOREOBJECT_SECRET_KEY=.*|AWS_S3_STOREOBJECT_SECRET_KEY=$(escape_sed "$AWS_S3_STOREOBJECT_SECRET_KEY")|;
            s|^AWS_S3_STOREOBJECT_REGION=.*|AWS_S3_STOREOBJECT_REGION=$(escape_sed "$AWS_S3_STOREOBJECT_REGION")|;
            s|^AWS_S3_STOREOBJECT_BUCKET=.*|AWS_S3_STOREOBJECT_BUCKET=$(escape_sed "$AWS_S3_STOREOBJECT_BUCKET")|;
        }
        /^# Used for Bulk issuance/,/^$/ {
            s|^AWS_ACCESS_KEY=.*|AWS_ACCESS_KEY=$(escape_sed "$AWS_ACCESS_KEY")|;
            s|^AWS_SECRET_KEY=.*|AWS_SECRET_KEY=$(escape_sed "$AWS_SECRET_KEY")|;
            s|^AWS_REGION=.*|AWS_REGION=$(escape_sed "$AWS_REGION")|;
            s|^AWS_BUCKET=.*|AWS_BUCKET=$(escape_sed "$AWS_BUCKET")|;
        }
        /^# Used for Adding org-logo/,/^$/ {
            s|^AWS_PUBLIC_ACCESS_KEY=.*|AWS_PUBLIC_ACCESS_KEY=$(escape_sed "$AWS_PUBLIC_ACCESS_KEY")|;
            s|^AWS_PUBLIC_SECRET_KEY=.*|AWS_PUBLIC_SECRET_KEY=$(escape_sed "$AWS_PUBLIC_SECRET_KEY")|;
            s|^AWS_PUBLIC_REGION=.*|AWS_PUBLIC_REGION=$(escape_sed "$AWS_PUBLIC_REGION")|;
            s|^AWS_ORG_LOGO_BUCKET_NAME=.*|AWS_ORG_LOGO_BUCKET_NAME=$(escape_sed "$AWS_ORG_LOGO_BUCKET_NAME")|;
        }
        s|^SHORTENED_URL_DOMAIN=.*|SHORTENED_URL_DOMAIN=https://s3.$(escape_sed "$AWS_S3_STOREOBJECT_REGION").amazonaws.com/$(escape_sed "$AWS_S3_STOREOBJECT_BUCKET")|;
    " .env || {
        print_message "red" "Failed to update .env file"
        exit 1
    }
    sed_inplace "s|your-ip|$(escape_sed "$MACHINE_IP")|g" agent.env

    # Postgres installation and env update regarding postgres
    USE_EXISTING_POSTGRES=false
    DOCKER_COMPOSE_POSTGRES=docker-compose.postgres.yml

    if prompt_yes_no "Do you want to use an existing PostgreSQL server?"; then
        print_message "blue" "Configuring external PostgreSQL connection"
        USE_EXISTING_POSTGRES=true
        handle_existing_value "POSTGRES_HOST" "Enter PostgreSQL host"
        
        while true; do
            handle_existing_value "POSTGRES_PORT" "Enter PostgreSQL port"
            [[ $POSTGRES_PORT =~ ^[0-9]+$ ]] && break
            print_message "red" "Port must be a number"
        done
        
        handle_existing_value "POSTGRES_USER" "Enter PostgreSQL username"
        handle_existing_value "POSTGRES_PASSWORD" "Enter PostgreSQL password"
        handle_existing_value "POSTGRES_DB" "Enter PostgreSQL database name"

        sed_inplace "
            s|^POSTGRES_HOST=.*|POSTGRES_HOST=$(escape_sed "$POSTGRES_HOST")|;
            s|^POSTGRES_PORT=.*|POSTGRES_PORT=$(escape_sed "$POSTGRES_PORT")|;
            s|^POSTGRES_USER=.*|POSTGRES_USER=$(escape_sed "$POSTGRES_USER")|;
            s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(escape_sed "$POSTGRES_PASSWORD")|;
            s|^POSTGRES_DB=.*|POSTGRES_DB=$(escape_sed "$POSTGRES_DB")|;
            s|^WALLET_STORAGE_HOST=.*|WALLET_STORAGE_HOST=$(escape_sed "$POSTGRES_HOST")|;
            s|^WALLET_STORAGE_PORT=.*|WALLET_STORAGE_PORT=$(escape_sed "$POSTGRES_PORT")|;
            s|^WALLET_STORAGE_USER=.*|WALLET_STORAGE_USER=$(escape_sed "$POSTGRES_USER")|;
            s|^WALLET_STORAGE_PASSWORD=.*|WALLET_STORAGE_PASSWORD=$(escape_sed "$POSTGRES_PASSWORD")|;
            s|^DATABASE_URL=.*|DATABASE_URL=postgresql://$(escape_sed "$POSTGRES_USER"):$(escape_sed "$POSTGRES_PASSWORD")@$(escape_sed "$POSTGRES_HOST"):$(escape_sed "$POSTGRES_PORT")/$(escape_sed $POSTGRES_DB)|;
            s|^POOL_DATABASE_URL=.*|POOL_DATABASE_URL=postgresql://$(escape_sed "$POSTGRES_USER"):$(escape_sed "$POSTGRES_PASSWORD")@$(escape_sed "$POSTGRES_HOST"):$(escape_sed "$POSTGRES_PORT")/$(escape_sed $POSTGRES_DB)|;
        " .env
        print_message "green" "Existing PostgreSQL configuration saved"
    else
        cat <<EOF >${DOCKER_COMPOSE_POSTGRES}
version: '3'

services:
  postgres:
    container_name: credebl-postgres
    image: postgres:16
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    ports:
      - "${USED_PORT_POSTGRES}:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: credebl
    volumes:
      - platform-volume:/var/lib/postgresql/data
      - ./init-db:/docker-entrypoint-initdb.d
volumes:
  platform-volume:
EOF
    postgres_setup=true
    fi

    sed_inplace "
    s|^SERVER_URL=.*|SERVER_URL=http://$MACHINE_IP:${USED_PORT_SCHEMA_FILE_SERVER}|;
    " agent.env
    print_message "green" "Environment file configured successfully."
    USE_EXISTING_KEYCLOAK_DB=false
    CREATE_KEYCLOAK_DB=false
    if prompt_yes_no "Do you want to use an existing PostgreSQL server for Keycloak?"; then
        print_message "blue" "Configuring external PostgreSQL connection for Keycloak"
        USE_EXISTING_KEYCLOAK_DB=true

        handle_existing_value "KEYCLOAK_DB_HOST" "Enter Keycloak DB host"

        while true; do
            handle_existing_value "KEYCLOAK_DB_PORT" "Enter Keycloak DB port"
            [[ $KEYCLOAK_DB_PORT =~ ^[0-9]+$ ]] && break
            print_message "red" "Port must be a number"
        done

        handle_existing_value "KEYCLOAK_DB_USER" "Enter Keycloak DB username"
        handle_existing_value "KEYCLOAK_DB_PASSWORD" "Enter Keycloak DB password"
        handle_existing_value "KEYCLOAK_DB_NAME" "Enter Keycloak DB name"

        print_message "green" "Existing Keycloak PostgreSQL configuration saved."

    else
        print_message "yellow" "Keycloak DB will be created in credebl-postgres."

        USE_EXISTING_KEYCLOAK_DB=false

        # These values will be used inside the Keycloak DB created in Docker
        KEYCLOAK_DB_NAME="keycloak"
        KEYCLOAK_DB_USER="postgres"
        KEYCLOAK_DB_PASSWORD="postgres"
        KEYCLOAK_DB_HOST="${MACHINE_IP}"
        KEYCLOAK_DB_PORT="${USED_PORT_POSTGRES}"

        # Mark that the DB must be created
        CREATE_KEYCLOAK_DB=true
    fi

    if [ "$CREATE_KEYCLOAK_DB" = true ]; then
    mkdir -p init-db

    cat <<EOF > init-db/create_keycloak_db.sql
CREATE DATABASE keycloak;
EOF

    print_message "green" "Keycloak database initialization SQL created."
fi

}

# Check docker and node, if not available installs node
install_nodejs() {
    # Check and install Node.js if needed
    if ! command_exists -v node &> /dev/null; then
        print_message "yellow" "Node.js not found. Installing..."
        
        if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
            # Linux installation
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs || {
                print_message "red" "Failed to install Node.js"
                exit 1
            }
        elif [[ "$OS_ID" == "Darwin" ]]; then
            # macOS installation
            if ! command_exists -v brew &> /dev/null; then
                print_message "red" "Homebrew required but not found. Install via: https://brew.sh"
                exit 1
            fi
            brew install node || {
                print_message "red" "Failed to install Node.js"
                exit 1
            }
        else
            print_message "red" "Unsupported OS for Node.js installation"
            exit 1
        fi
        print_message "green" "Node.js installed successfully"
    else
        print_message "green" "Node.js already installed"
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        OS_ID=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        OS_ID=$(uname -s)
    fi
}

install_docker() {
    case "$OS_ID" in
        "ubuntu")
            install_docker_ubuntu
            ;;
        "debian")
            install_docker_debian
            ;;
        "Darwin")
            install_docker_macos
            ;;
        *)
            print_message "red" "Unsupported OS: $OS_ID"
            exit 1
            ;;
    esac
}

install_docker_ubuntu() {
    print_message "blue" "Detected Ubuntu. Checking Docker installation..."
    
    if ! command_exists docker || ! docker compose version &> /dev/null; then
        print_message "yellow" "Installing Docker on Ubuntu..."
        
        sudo apt-get update || {
            print_message "red" "Failed to update apt packages"
            exit 1
        }
        
        sudo apt-get install -y ca-certificates curl gnupg || {
            print_message "red" "Failed to install prerequisites"
            exit 1
        }
        
        sudo install -m 0755 -d /etc/apt/keyrings || {
            print_message "red" "Failed to create keyrings directory"
            exit 1
        }
        
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || {
            print_message "red" "Failed to download Docker GPG key"
            exit 1
        }
        
        sudo chmod a+r /etc/apt/keyrings/docker.asc || {
            print_message "red" "Failed to set keyring permissions"
            exit 1
        }
        
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
            $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || {
                print_message "red" "Failed to add Docker repository"
                exit 1
            }
        
        sudo apt-get update || {
            print_message "red" "Failed to update apt after adding Docker repo"
            exit 1
        }
        
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
            print_message "red" "Failed to install Docker packages"
            exit 1
        }
        
        print_message "green" "Docker installed successfully."
        sudo systemctl start docker || {
            print_message "red" "Failed to start Docker service"
            exit 1
        }
        sudo systemctl enable docker || {
            print_message "red" "Failed to enable Docker service"
            exit 1
        }
        sudo usermod -aG docker $USER && newgrp docker || {
            print_message "red" "Failed to add $USER to docker group"
            exit 1
        }
    else
        print_message "green" "Docker and Docker Compose are already installed."
    fi
}

install_docker_debian() {
    print_message "blue" "Detected Debian. Checking Docker installation..."
    
    if ! command_exists docker; then
        print_message "red" "Docker is not installed. Please install Docker manually on Debian."
        exit 1
    else
        print_message "green" "Docker is already installed."
    fi
    
    if ! docker compose version &> /dev/null; then
        print_message "red" "Docker Compose is not installed. Please install Docker Compose."
        exit 1
    else
        print_message "green" "Docker Compose is available."
    fi
}

install_docker_macos() {
    print_message "blue" "Detected macOS. Checking Docker installation..."
    if ! command -v psql >/dev/null 2>&1; then
    echo "psql not found. Installing PostgreSQL via Homebrew..."

    # Install PostgreSQL (includes psql)
    brew install postgresql

    # Add Homebrew paths (Apple Silicon + Intel support)
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

    echo "PostgreSQL installed. psql is now available."
    else
    echo "psql already installed."
    fi
    
    # Ensure macOS has Homebrew paths correctly set for psql and other tools
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    echo "PATH updated for Homebrew tools."

    if ! command_exists docker; then
        print_message "red" "Docker is not installed. Please install Docker Desktop for macOS. \
        You can refer to this URL: https://docs.docker.com/desktop/setup/install/mac-install/"
        exit 1
    else
        print_message "green" "Docker is already installed."
    fi
    
    if ! docker compose version &> /dev/null; then
        print_message "red" "Docker Compose is not installed. Please install Docker Compose."
        exit 1
    else
        print_message "green" "Docker Compose is available."
    fi
}

# Step 3: Install Terraform
install_terraform() {
    print_message "blue" "Checking Terraform installation..."
    
    if command_exists terraform; then
        print_message "green" "Terraform is already installed."
        return 0
    fi
    
    local OS_ID
    if [ -f /etc/os-release ]; then
        OS_ID=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        OS_ID=$(uname -s)
    fi

    case "$OS_ID" in
        "ubuntu"|"debian")
            install_terraform_linux
            ;;
        "Darwin")
            install_terraform_macos
            ;;
        *)
            print_message "red" "Unsupported OS for Terraform installation: $OS_ID"
            exit 1
            ;;
    esac
}

install_terraform_linux() {
    print_message "yellow" "Installing Terraform on Linux..."
    
    sudo apt-get update && sudo apt-get install -y gnupg software-properties-common || {
        print_message "red" "Failed to install prerequisites for Terraform"
        exit 1
    }
    
    wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null || {
        print_message "red" "Failed to add HashiCorp GPG key"
        exit 1
    }
    
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list || {
        print_message "red" "Failed to add HashiCorp repository"
        exit 1
    }
    
    sudo apt update || {
        print_message "red" "Failed to update apt after adding HashiCorp repo"
        exit 1
    }
    
    sudo apt-get install terraform || {
        print_message "red" "Failed to install Terraform"
        exit 1
    }
    
    print_message "green" "Terraform installed successfully."
}

install_terraform_macos() {
    print_message "yellow" "Installing Terraform on macOS..."
    
    if ! command_exists brew; then
        print_message "red" "Homebrew is not installed. Please install Homebrew first."
        exit 1
    fi
    
    brew tap hashicorp/tap || {
        print_message "red" "Failed to tap hashicorp/tap"
        exit 1
    }
    
    brew install hashicorp/tap/terraform || {
        print_message "red" "Failed to install Terraform"
        exit 1
    }
    
    print_message "green" "Terraform installed successfully."
}

# Step 4: Deploy Keycloak and Postgres
deploy_keycloak() {
    local reuse_existing=false
    local desired_port=${USED_PORT_KEYCLOAK}
    local KC_ENV_FILE="./keycloak.env"
    print_message "purple" "Setting up Keycloak..."

    cat > $KC_ENV_FILE <<EOF
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin

KC_HTTP_ENABLED=true
KC_DB=postgres
KC_DB_URL=jdbc:postgresql://$KEYCLOAK_DB_HOST:$KEYCLOAK_DB_PORT/keycloak
KC_DB_USERNAME=$KEYCLOAK_DB_USER
KC_DB_PASSWORD=$KEYCLOAK_DB_PASSWORD
KC_DB_URL_PORT=$KEYCLOAK_DB_PORT

KC_HOSTNAME_ADMIN_URL=http://$MACHINE_IP:$USED_PORT_KEYCLOAK/
KC_HOSTNAME_URL=http://$MACHINE_IP:$USED_PORT_KEYCLOAK/

KC_PROXY=edge
KC_HOSTNAME_STRICT=false
KC_LOG=console
KC_HOSTNAME_STRICT_HTTPS=false

KC_HTTPS_ENABLED=false
EOF

    if [[ "${postgres_setup:-false}" == true ]]; then
        docker compose -f "$DOCKER_COMPOSE_POSTGRES" up -d
    fi
    docker compose -f docker-compose.nats.yml up -d
    docker compose -f docker-compose.redis.yml up -d
    sleep 30
    if docker ps -a --format '{{.Names}} {{.Image}}' | grep -q "credebl-keycloak.*${KEYCLOAK_VERSION}"; then
        keycloak_container=$(docker ps -a --format '{{.Names}} {{.Image}}' | grep "credebl-keycloak.*${KEYCLOAK_VERSION}" | awk '{print $1}')
        print_message "yellow" "Found existing Keycloak container ($keycloak_container) with matching version"
        reuse_existing=true
        
        # Check if the container is running
        container_running=$(docker inspect -f '{{.State.Running}}' "$keycloak_container")

        if [ "$container_running" = "true" ]; then
            current_port=$(docker port "$keycloak_container" 8080/tcp | cut -d: -f1)
            
            if [ "$current_port" != "$desired_port" ]; then
                print_message "yellow" "Port mismatch (current: $current_port, desired: $desired_port). Recreating container..."
                docker rm -f "$keycloak_container" || {
                    print_message "red" "Failed to remove existing container"
                    exit 1
                }
                reuse_existing=false
            fi
        else
            print_message "yellow" "Keycloak container exists but is stopped. Reusing container if port matches..."

            # Get the port mapping from container config (even if stopped)
            host_port=$(docker inspect -f '{{range $p, $conf := .HostConfig.PortBindings}}{{$p}} -> {{(index $conf 0).HostPort}}{{end}}' "$keycloak_container" | grep '^8080/tcp' | awk '{print $NF}')

            if [ "$host_port" != "$desired_port" ]; then
                print_message "yellow" "Port mismatch for stopped container (current: $host_port, desired: $desired_port). Recreating container..."
                docker rm -f "$keycloak_container" || {
                    print_message "red" "Failed to remove existing container"
                    exit 1
                }
                reuse_existing=false
            fi
        fi
    fi

    if [ "$reuse_existing" = false ]; then
        # Determine container name
        local container_name="credebl-keycloak"

        # Check if name is already in use
        if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            container_name="credebl-keycloak-${desired_port}"
            print_message "yellow" "Keycloak name in use, using alternative: $container_name"
        fi

        print_message "blue" "Starting new Keycloak container on port $desired_port..."
        docker run -d \
            -p ${desired_port}:8080 \
            --name "$container_name" \
            --env-file $KC_ENV_FILE \
            -e KEYCLOAK_ADMIN=admin \
            -e KEYCLOAK_ADMIN_PASSWORD=admin \
            quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} start-dev && \
            print_message "green" "Keycloak started successfully" || {
                print_message "red" "Failed to start Keycloak container"
                exit 1
            }
    else
        # Ensure existing container is running
        if [ "$(docker inspect -f '{{.State.Running}}' "$keycloak_container")" = "false" ]; then
            docker start "$keycloak_container" && \
                print_message "green" "Restarted existing Keycloak container" || {
                    print_message "red" "Failed to restart Keycloak container"
                    exit 1
                }
        else
            print_message "green" "Using existing Keycloak container ($keycloak_container)"
        fi
    fi
}

# Step 5: Setup Keycloak using Terraform
setup_keycloak_terraform() {
    print_message "blue" "Setting up Keycloak via Terraform..."
    NEW_URL="\"http://${MACHINE_IP}:${USED_PORT_KEYCLOAK}\""
    REDIRECT_URL="\"http://${MACHINE_IP}:${USED_PORT_STUDIO}\""
    
    if [ ! -d "${TERRAFORM_DIR}" ]; then
        print_message "red" "Terraform directory not found: ${TERRAFORM_DIR}"
        exit 1
    fi
    
    cd "${TERRAFORM_DIR}" || {
        print_message "red" "Failed to change directory to ${TERRAFORM_DIR}"
        exit 1
    }

    if grep -q '^root_url' terraform.tfvars ; then
        sed_inplace "s|^root_url = .*|root_url = ${NEW_URL}|" terraform.tfvars
        sed_inplace "s|^redirect_url = .*|redirect_url = ${REDIRECT_URL}|" terraform.tfvars
        print_message "green" "Keycloak root URL set to ${NEW_URL} and redirect url set to ${REDIRECT_URL}"
    else
        print_message "red"   "Failed to set keycloak root url in terraform.tfvars"
    fi
    
    terraform init || {
        print_message "red" "Terraform init failed"
        exit 1
    }
    
    print_message "yellow" "Waiting 30 seconds for Keycloak to be fully ready..."
    sleep 40
    
    terraform apply -auto-approve || {
        print_message "red" "Terraform apply failed"
        exit 1
    }
    
    print_message "green" "Keycloak setup completed via Terraform."
}

# Step 6: Update environment with Keycloak secret and JWT_token
update_keycloak_secret() {
    print_message "blue" "Updating environment with Keycloak secret..."
    KEYCLOAK_URL="http://${MACHINE_IP}:${USED_PORT_KEYCLOAK}"
    
    if [ ! -f "secret.env" ]; then
        print_message "red" "secret.env not found! Could not insert KEYCLOAK_MANAGEMENT_CLIENT_SECRET."
        return 1
    fi
    
    CLIENT_SECRET=$(grep ADMIN_CLIENT_SECRET secret.env | cut -d '=' -f2)
    if [ -z "$CLIENT_SECRET" ]; then
        print_message "red" "Failed to extract ADMIN_CLIENT_SECRET from secret.env"
        return 1
    fi
    
    cd "${ROOT_DIR}" || {
        print_message "red" "Failed to change directory to ${ROOT_DIR}"
        exit 1
    }

    sed_inplace "
    s|^KEYCLOAK_DOMAIN=.*|KEYCLOAK_DOMAIN=$(escape_sed "$KEYCLOAK_URL")/|;
    s|^KEYCLOAK_ADMIN_URL=.*|KEYCLOAK_ADMIN_URL=$(escape_sed "$KEYCLOAK_URL")|;
    " .env || {
        print_message "red" "Failed to update Keycloak root url in .env"
        return 1
    }

    if grep -q "KEYCLOAK_MANAGEMENT_CLIENT_SECRET" .env; then
        sed_inplace "s/^KEYCLOAK_MANAGEMENT_CLIENT_SECRET=.*/KEYCLOAK_MANAGEMENT_CLIENT_SECRET=$CLIENT_SECRET/" .env || {
            print_message "red" "Failed to update KEYCLOAK_MANAGEMENT_CLIENT_SECRET in .env"
            return 1
        }
    else
        echo "KEYCLOAK_MANAGEMENT_CLIENT_SECRET=$CLIENT_SECRET" >> .env || {
            print_message "red" "Failed to append KEYCLOAK_MANAGEMENT_CLIENT_SECRET to .env"
            return 1
        }
    fi
    
    print_message "green" "Keycloak secret updated in .env successfully."
}

generate_secret() {
    print_message "blue" "Generating JWT secret..."
    
    install_nodejs
    escape_for_sed_replacement() {
    printf '%s' "$1" \
        | sed 's/[&|]/\\&/g'
    }
    # Extract values from .env file
    CLIENT_ID=$(grep '^KEYCLOAK_MANAGEMENT_CLIENT_ID=' .env | cut -d '=' -f2-)
    CRYPTO_PRIVATE_KEY=$(grep '^CRYPTO_PRIVATE_KEY=' .env | cut -d '=' -f2-)

    # Generate secure random secret
    JWT_TOKEN_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))" 2>/dev/null)
    
    if [[ -z "$JWT_TOKEN_SECRET" ]]; then
        print_message "red" "Failed to generate JWT secret"
        exit 1
    fi

    if openssl enc -aes-256-cbc -pbkdf2 -k test < /dev/null >/dev/null 2>&1; then
        OPENSSL_ARGS="-aes-256-cbc -a -salt -pbkdf2 -iter 100000"
    else
        OPENSSL_ARGS="-aes-256-cbc -a -salt"
        print_message "yellow" "OpenSSL too old, using deprecated key derivation."
    fi

    AES_ENCRYPTED_CLIENT_ID=$(echo -n "$CLIENT_ID" | openssl enc $OPENSSL_ARGS -pass pass:"$CRYPTO_PRIVATE_KEY" | tr -d '\n')
    AES_ENCRYPTED_CLIENT_SECRET=$(echo -n "$CLIENT_SECRET" | openssl enc $OPENSSL_ARGS -pass pass:"$CRYPTO_PRIVATE_KEY" | tr -d '\n')
    new_secret=$(escape_for_sed_replacement "$JWT_TOKEN_SECRET")

    # Update .env file
    sed_inplace \
    -e "s|^JWT_TOKEN_SECRET=.*|JWT_TOKEN_SECRET=$new_secret|" \
    -e "s|^CREDEBL_KEYCLOAK_MANAGEMENT_CLIENT_ID=.*|CREDEBL_KEYCLOAK_MANAGEMENT_CLIENT_ID='$(escape_sed "$AES_ENCRYPTED_CLIENT_ID")'|" \
    -e "s|^CREDEBL_KEYCLOAK_MANAGEMENT_CLIENT_SECRET=.*|CREDEBL_KEYCLOAK_MANAGEMENT_CLIENT_SECRET='$(escape_sed "$AES_ENCRYPTED_CLIENT_SECRET")'|" \
    .env || {
        print_message "red" "Failed to update secrets in .env"
        return 1
    }

    print_message "green" "JWT secret generated and stored successfully"
}
# Step 7: Pull credo-controller image
pull_credo_controller() {
    print_message "blue" "Pulling credo-controller image..."
    
    docker pull ghcr.io/credebl/credo-controller:latest || {
        print_message "red" "Failed to pull credo-controller image"
        exit 1
    }
    
    print_message "green" "credo-controller image pulled successfully."
}

update_master_table() {
    print_message "blue" "Updating master table configuration..."

    sudo npm install -g pnpm
    pnpm i
    cd $MASTER_TABLE_FILE || {
        print_message "red" "Failed to change directory to $MASTER_TABLE_FILE"
        exit 1
    }
    
    if [ -z "$SENDGRID_API_KEY" ] || [ -z "$EMAIL_FROM" ]; then
        print_message "red" "SendGrid API key and sender email cannot be empty"
        exit 1
    fi
    
    sed_inplace "s|##Machine Ip Address/Domain for agent setup##|$MACHINE_IP|g" credebl-master-table.json || {
        print_message "red" "Failed to update machine IP in master table"
        exit 1
    }
    
    sed_inplace "s|## Platform API Ip Address##|http://$MACHINE_IP:5000|g" credebl-master-table.json || {
        print_message "red" "Failed to update platform API IP in master table"
        exit 1
    }
    
    sed_inplace "s|##Machine Ip Address for agent setup##|http://$MACHINE_IP:5000|g" credebl-master-table.json || {
        print_message "red" "Failed to update agent setup IP in master table"
        exit 1
    }
    
    sed_inplace "s|###Sendgrid Key###|$SENDGRID_API_KEY|g" credebl-master-table.json || {
        print_message "red" "Failed to update SendGridAgent-Provisioning-Service Microservice is listening to NATS key in master table"
        exit 1
    }
    
    sed_inplace "s|##Senders Mail ID##|$EMAIL_FROM|g" credebl-master-table.json || {
        print_message "red" "Failed to update sender email in master table"
        exit 1
    }
    
    print_message "green" "Master table configuration updated successfully."
}

prisma_setup() {
    cd ../../..
    npx prisma generate
    npx prisma migrate deploy
    npx prisma db seed
    cd ../..
}

setup_schema_service(){

    print_message "blue" "Setting up Schema Service..."
    docker rm schema-file-server -f
    docker run -d \
            -p ${USED_PORT_SCHEMA_FILE_SERVER}:4001 \
            --name schema-file-server \
            --env-file .env \
            -v "$PWD/apps/schemas:/app/schemas" \
            ghcr.io/credebl/schema-file-server:latest && \
            print_message "green" "Schema file server started successfully" || {
        print_message "red" "Failed to start schema file service"
        exit 1
    }

    sleep 20
    print_message "blue" "Updating environment with Schema File Server details..."
    
    # Wait for schema-file-server to start and get auth token
    local SCHEMA_FILE_SERVER_TOKEN
    local FILE_SERVER_TOKEN
    SCHEMA_FILE_SERVER_TOKEN=$(docker logs schema-file-server 2>&1 | grep "Auth Token:" | awk '{print $3}' | head -n 1)
    
    if [[ -z "$SCHEMA_FILE_SERVER_TOKEN" ]]; then
        print_message "red" "Failed to get Schema File Server auth token"
        exit 1
    fi

    # Update .env file
    sed_inplace "
        s/^SCHEMA_FILE_SERVER_TOKEN=.*/SCHEMA_FILE_SERVER_TOKEN=${SCHEMA_FILE_SERVER_TOKEN}/;
    " .env || {
        print_message "red" "Failed to update Schema File Server configuration in .env"
        exit 1
    }

    sed_inplace "
        s/^FILE_SERVER_TOKEN=.*/FILE_SERVER_TOKEN=${SCHEMA_FILE_SERVER_TOKEN}/;
    " agent.env || {
        print_message "red" "Failed to update Schema File Server configuration in agent.env"
        exit 1
    }

    echo "Enter password to grant execute permission for saving schemas..."
    sudo chmod 777 $PWD/apps/schemas
    print_message "green" "Schema File Server configuration updated successfully"
}

configure_env() {
    # Path to your .env file (adjust if needed)

    sed_inplace "
        s|^AFJ_AGENT_TOKEN_PATH=/agent-provisioning/AFJ/token/|#AFJ_AGENT_TOKEN_PATH=/agent-provisioning/AFJ/token/|;
        s|^AFJ_AGENT_SPIN_UP=/agent-provisioning/AFJ/scripts/docker_start_agent.sh|#AFJ_AGENT_SPIN_UP=/agent-provisioning/AFJ/scripts/docker_start_agent.sh|;
        s|^AFJ_AGENT_ENDPOINT_PATH=/agent-provisioning/AFJ/endpoints/|#AFJ_AGENT_ENDPOINT_PATH=/agent-provisioning/AFJ/endpoints/|;
        s|^# AFJ_AGENT_TOKEN_PATH=/apps/agent-provisioning/AFJ/token/|AFJ_AGENT_TOKEN_PATH=/apps/agent-provisioning/AFJ/token/|;
        s|^# AFJ_AGENT_SPIN_UP=/apps/agent-provisioning/AFJ/scripts/start_agent.sh|AFJ_AGENT_SPIN_UP=/apps/agent-provisioning/AFJ/scripts/start_agent.sh|;
        s|^# AFJ_AGENT_ENDPOINT_PATH=/apps/agent-provisioning/AFJ/endpoints/|AFJ_AGENT_ENDPOINT_PATH=/apps/agent-provisioning/AFJ/endpoints/|;
    " .env
    
    echo "Configured .env file for local execution"
}

start_all() {
    if [[ "$OS_ID" == "Darwin" ]]; then
        start_services_macos
    else
        start_services
    fi
}

start_services_macos() {
    echo ""
    echo "============================================"
    echo " macOS detected — skipping auto-start"
    echo "============================================"
    echo "You can now start your services manually using pnpm."
    echo "  cd to the platform root directory and run:"
    echo "Examples:"
    echo "  pnpm run start                # API gateway"
    echo "  pnpm run start user           # User Service"
    echo "  pnpm run start utility        # Utility Service"
    echo "  pnpm run start connection     # Connection Service"
    echo "  pnpm run start ledger         # Ledger Service"
    echo "  pnpm run start organization   # Organization Service"
    echo "  pnpm run start agent-provisioning"
    echo "  pnpm run start agent-service"
    echo "  pnpm run start issuance"
    echo "  pnpm run start verification"
    echo "  pnpm run start webhook"
    echo "  pnpm run start geo-location"
    echo "  pnpm run start cloud-wallet"
}

start_services() {
    configure_env
    
    # Start services in separate terminals
    gnome-terminal --tab --title="Api-gateway" -- bash -c "pnpm run start; exec bash"
    sleep 10    
    gnome-terminal --tab --title="User Service" -- bash -c "pnpm run start user; exec bash"
    sleep 10
    gnome-terminal --tab --title="Utility Service" -- bash -c "pnpm run start utility; exec bash"
    sleep 10
    gnome-terminal --tab --title="Connection Service" -- bash -c "pnpm run start connection; exec bash"
    sleep 10
    gnome-terminal --tab --title="Ledger Service" -- bash -c "pnpm run start ledger; exec bash"
    sleep 10
    gnome-terminal --tab --title="Organization Service" -- bash -c "pnpm run start organization; exec bash"
    sleep 10

    # Start agent-provisioning and wait for it to be ready
    gnome-terminal --tab --title="Agent Provisioning" -- bash -c \
    "pnpm run start agent-provisioning | while read -r line; do \
        echo \"\$line\"; \
        if [[ \"\$line\" == *\"Agent-Provisioning-Service Microservice is listening to NATS\"* ]]; then \
            gnome-terminal --tab --title=\"Agent Service\" -- bash -c \"pnpm run start agent-service; exec bash\"; \
        fi; \
    done; exec bash"
    
    # Start remaining services
    sleep 10
    gnome-terminal --tab --title="Issuance Service" -- bash -c "pnpm run start issuance; exec bash"
    sleep 10
    gnome-terminal --tab --title="Verification Service" -- bash -c "pnpm run start verification; exec bash"
    sleep 10
    gnome-terminal --tab --title="Webhook Service" -- bash -c "pnpm run start webhook; exec bash"
    sleep 10
    gnome-terminal --tab --title="Geolocation Service" -- bash -c "pnpm run start geo-location; exec bash"
    sleep 10
    gnome-terminal --tab --title="Cloud Wallet Service" -- bash -c "pnpm run start cloud-wallet; exec bash"
}

main(){
    clone_platform
    prepare_env_file
    configure_ports
    prepare_environment_variable
    detect_os
    install_docker
    install_terraform
    deploy_keycloak
    setup_keycloak_terraform
    update_keycloak_secret
    generate_secret
    pull_credo_controller
    update_master_table
    prisma_setup
    setup_schema_service
    start_all
}

main