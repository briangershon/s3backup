s3backup
========

A simple folder backup solution to AWS S3.

Job configuration is downloaded from S3 allowing easy changes from a central
location instead of separate config files on each machine.

Author: Brian Gershon

License: MIT

Usage
-----

    ./s3backup.rb job backup_job_s3_key, aws_bucket, aws_region, aws_profile

Example:

    ./s3backup.rb job laptop_backup_job.yml my-bucket us-west-2 brian

Description:

`aws_bucket` is a string like `my-s3-bucket`

`aws_region` is a string like `us-west-2`

`aws_profile` is a profile name in ~/.aws/credentials

`backup_job_s3_key` is the name (s3_key) of a YAML file in aws_bucket that looks like this:

```
---
backup_base_path: /Volumes
backup_folder: /Volumes/stuff/**/*
backup_folder_excludes:
- /Volumes/stuff/Lib/
- /Volumes/stuff/cache/
```

`backup_folder` is the absolute path of the folder you want to backup, recursively.

`backup_base_path` is the part that is stripped off the beginning to determine the S3 key.

`backup_folder_excludes` is an array of absolute paths to exclude from the backup_folder.
