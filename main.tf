terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.34.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials_file)
  region  = "us-east1"
}

variable "credentials_file" {
  type        = string
  description = "The path to the GCP service account key JSON file"
  default     = "sa_key.json"
}

resource "random_id" "bucket_prefix" {
  byte_length = 8
}

resource "google_storage_bucket" "bucket" {
  name                        = "${random_id.bucket_prefix.hex}-gcf-source"
  location                    = "US"
  uniform_bucket_level_access = true
}

data "archive_file" "source_zip" {
  type        = "zip"
  source_dir  = "${path.module}/source"
  output_path = "${path.module}/function-source.zip"
}

resource "google_storage_bucket_object" "object" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = data.archive_file.source_zip.output_path
}

resource "google_cloudfunctions2_function" "function" {
  name        = "function-v2"
  location    = "us-east1"
  description = "a new function"

  build_config {
    runtime     = "nodejs18"
    entry_point = "helloHttp"
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
  }
}

output "function_uri" {
  value       = google_cloudfunctions2_function.function.service_config[0].uri
  description = "The URI of the deployed Cloud Function."
}
