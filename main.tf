terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.34.0"
    }
  }
  
  backend "gcs" {
    bucket = "test-serverless-terraform-state-bucket"
    prefix = "terraform/state"
  }
}

provider "google" {
  credentials = file(var.credentials_file)
  project = var.project_id
  region  = var.region_name
}

variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

variable "region_name" {
  type        = string
  description = "The GCP region name"
}

variable "credentials_file" {
  type        = string
  description = "The path to the GCP service account key JSON file"
  default     = "sa_key.json"
}

variable "create_zip" {
  type        = bool
  description = "Whether to create the source zip file or not"
  default     = true
}

resource "random_id" "bucket_prefix" {
  byte_length = 8
}

resource "google_storage_bucket" "bucket" {
  name                        = "${random_id.bucket_prefix.hex}-gcf-source"
  location                    = "us-east1"
  uniform_bucket_level_access = true
}

data "archive_file" "source_zip" {
  count       = var.create_zip ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/source/dist"
  output_path = "${path.module}/function-source.zip"
}

resource "google_storage_bucket_object" "object" {
  count  = var.create_zip ? 1 : 0
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = data.archive_file.source_zip[0].output_path
}

resource "google_cloudfunctions2_function" "function" {
  name        = "function-v2"
  location    = "us-east1"
  description = "a new function"

  build_config {
    runtime     = "nodejs18"
    entry_point = "api"
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = var.create_zip ? google_storage_bucket_object.object[0].name : ""
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
  }
}

resource "google_cloud_run_service_iam_binding" "allowUnauthenticated" {
  project = google_cloudfunctions2_function.function.project
  location = google_cloudfunctions2_function.function.location
  service = google_cloudfunctions2_function.function.name
  role = "roles/run.invoker"
  members = [
    "allUsers",
  ]
}

output "function_uri" {
  value       = google_cloudfunctions2_function.function.service_config[0].uri
  description = "The URI of the deployed Cloud Function."
}
