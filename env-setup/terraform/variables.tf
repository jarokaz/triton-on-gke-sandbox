# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


variable "project_id" {
    description = "The GCP project ID"
    type        = string
}

variable "region" {
    description = "The region for the environment resources"
    type        = string
}

variable "zone" {
    description = "The zone for a Vertex Notebook instance"
    type        = string
}


variable "repository_bucket_name" {
    description = "The GCS bucket name to be used as model repository"
    type        = string
}

variable "force_destroy" {
    description = "Force destroy flag for the GCS bucket"
    default = true 
}

variable "cluster_name" {
    description = "The name of the GKE cluster"
    type        = string
}

variable "cluster_description" {
    description = "The cluster's description"
    default = "GKE cluster to host NVIDIA Triton"
}


variable "triton_node_count" {
    description = "The GPU pool node count"
    default     = 1
}

variable "disk_size_gb" {
    description = "Disk size on a Triton node"
    default = 500
}

variable "disk_type" {
    description = "Disk typ on a Triton node"
    default = "pd-standard"
}

variable "triton_sa_name" {
    description = "The service account name for Triton workload identity."
    default = "triton-sa"
}

variable "triton_sa_roles" {
  description = "The roles to assign to the Triton service account"
  default = [
    "roles/storage.objectViewer",
    ] 
}

variable "triton_namespace" {
    description = "The K8s namespace for Triton deployment."
    default = "default"
}


variable "network_name" {
    description = "The network name"
    type        = string
}

variable "subnet_name" {
    description = "The subnet name"
    type        = string
}

variable "subnet_ip_range" {
  description = "The IP address range for the subnet"
  default     = "10.129.0.0/20"
}

variable "pods_ip_range" {
    description = "The secondary IP range for pods"
    default     = "192.168.1.0/24"
}

variable "services_ip_range" {
    description = "The secondary IP range for services"
    default     = "192.168.2.0/24"
}


variable "machine_type" {
    description = "The a2 machine type for the Triton node pool"
    default = "a2-highgpu-1g"
}



