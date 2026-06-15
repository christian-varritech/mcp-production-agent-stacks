# GKE Cluster for MCP Production Agent Stacks
# 
# This Terraform configuration provisions:
# - Private GKE cluster with autoscaling
# - GPU node pool for self-hosted inference
# - VPC with private subnets
# - Cloud NAT for outbound connectivity

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "mcp-production-agent-stacks"
  }
}

variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE Cluster Name"
  type        = string
  default     = "mcp-agent-cluster"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# VPC Network
resource "google_compute_network" "mcp_vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_subnetwork" "mcp_subnet" {
  name                     = "${var.cluster_name}-subnet"
  ip_cidr_range            = "10.0.0.0/20"
  region                   = var.region
  network                  = google_compute_network.mcp_vpc.id
  private_ip_google_access = true
}

# Private GKE Cluster
resource "google_container_cluster" "mcp_cluster" {
  name     = var.cluster_name
  location = var.region
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  
  # Network configuration
  network    = google_compute_network.mcp_vpc.name
  subnetwork = google_compute_subnetwork.mcp_subnet.name
  
  # Node pool defaults
  node_pool {
    name       = "default-pool"
    node_count = 1
    
    management {
      auto_repair  = true
      auto_upgrade = true
    }
    
    node_config {
      machine_type = "e2-medium"
      
      workload_metadata_config {
        mode = "GKE_METADATA"
      }
    }
  }
  
  # Security configuration
  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.mcp_subnet.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.mcp_subnet.secondary_ip_range[1].range_name
  }
  
  # Enable addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }
  
  # Monitoring
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
    
    managed_prometheus {
      enabled = true
    }
  }
  
  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
  
  # Release channel for auto-upgrades
  release_channel {
    channel = "REGULAR"
  }
  
  depends_on = [
    google_compute_subnetwork.mcp_subnet
  ]
}

# GPU Node Pool for Inference
resource "google_container_node_pool" "gpu_pool" {
  name       = "gpu-inference-pool"
  location   = var.region
  cluster    = google_container_cluster.mcp_cluster.name
  node_count = 2
  
  autoscaling {
    min_node_count = 1
    max_node_count = 8
  }
  
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  node_config {
    machine_type = "g2-standard-8"
    
    guest_accelerator {
      type  = "nvidia-l4"
      count = 1
    }
    
    disk_size_gb = 200
    disk_type    = "pd-ssd"
    
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    taint {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }
}

# Cloud NAT for outbound connectivity
resource "google_compute_router" "mcp_router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.mcp_vpc.id
}

resource "google_compute_router_nat" "mcp_nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.mcp_router.name
  region                             = google_compute_router.mcp_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "GKE Cluster Endpoint"
  value       = google_container_cluster.mcp_cluster.endpoint
  sensitive   = true
}

output "cluster_name" {
  description = "GKE Cluster Name"
  value       = google_container_cluster.mcp_cluster.name
}

output "gpu_pool_name" {
  description = "GPU Node Pool Name"
  value       = google_container_node_pool.gpu_pool.name
}
