provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "terraform-gluejob" {
  bucket = "terraform-gluejob"
  acl    = "private"
}

resource "aws_s3_bucket_object" "covid_data" {
  bucket = aws_s3_bucket.terraform-gluejob.id
  key    = "covid_worldwide.csv"
  source = "C:\\Users\\psa97\\OneDrive\\Desktop\\s3_coviddata\\covid_worldwide.csv"

  # Set storage class to Glacier
  storage_class = "GLACIER"
}

# Create a lifecycle rule to transition objects to Glacier
resource "aws_s3_bucket_lifecycle_configuration" "terraform-gluejob" {
  bucket = aws_s3_bucket.terraform-gluejob.id

  rule {
    id      = "glacier-transition-rule"
    status  = "Enabled"

    transition {
      days          = 1
      storage_class = "GLACIER"
    }

    filter {
      prefix = ""
    }
  }
}

resource "aws_glue_catalog_database" "glue_db" {
  name = "glue_db"
}

resource "aws_glue_catalog_table" "glue_table" {
  name = "glue_table"

  # Define the storage descriptor with the S3 location of the data
  storage_descriptor {
    location = "s3://${aws_s3_bucket.terraform-gluejob.id}/covid_worldwide.csv"

    # Define the schema columns using the columns block
    columns {
      name = "country"
      type = "string"
    }

    columns {
      name = "cases"
      type = "int"
    }

    # Define the table parameters
    parameters = {
      "classification"         = "csv"
      "skip.header.line.count" = "1"
    }
  }

  # Define the database that this table belongs to
  database_name = aws_glue_catalog_database.glue_db.name

  # Add country as a partition key
  partition_keys {
    name = "country"
    type = "string"
  }
}
data "aws_glue_version" "latest" {
  version_prefix = "3."
}

resource "aws_glue_job" "glue_job" {
  name         = "glue_job"
  role_arn     = aws_iam_role.glue_job_role.arn
  glue_version = data.aws_glue_version.latest.version
  command {
    name           = "glueetl"
    script_location = "s3://${aws_s3_bucket.terraform-gluejob.id}/glue_script.py"
  }
}

  default_arguments = {
    "--job-bookmark-option": "job-bookmark-enable",
    "--enable-metrics": "",
    "--job-language": "python",
    "--enable-continuous-cloudwatch-log": "",
    "--partitionBy": "country",
    "--groupBy": "country",
    "--sortBy": "cases DESC"
  }
}


resource "aws_iam_role" "glue_job_role" {
  name = "glue_job_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "glue_job_policy" {
  name = "glue_job_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "glue:*"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_job_policy_attachment" {
  policy_arn = aws_iam_policy.glue_job_policy.arn
  role       = aws_iam_role.glue_job_role.name
}

