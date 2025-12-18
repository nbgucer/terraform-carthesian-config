variable "aks_cluster_name" {
  description = "Name of the existing AKS cluster"
  type        = string
}

variable "aks_resource_group_name" {
  description = "Resource group name of the existing AKS cluster"
  type        = string
}

variable "acr_name" {
  description = "Name of the existing Azure Container Registry"
  type        = string
}

variable "acr_resource_group_name" {
  description = "Resource group name of the existing ACR"
  type        = string
}

variable "docker_image_name" {
  description = "Name of the Docker image"
  type        = string
  default     = "multiconfigapp"
}

variable "docker_image_tag" {
  description = "Tag of the Docker image"
  type        = string
  default     = "latest"
}