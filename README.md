s3backup
========

A simple folder backup solution to AWS S3.

* Central configuration - Job configuration is downloaded from S3 allowing easy
changes from a central location instead of separate config files on each machine.

* Metadata Cache - File metadata is cached locally to avoid hitting S3 for each
file to check if it needs updating. Greatly speeds up subsequent runs.

Author: Brian Gershon

License: MIT

Usage
-----

    s3backup.rb job backup_job_s3_key aws_bucket aws_profile

Example:

    s3backup.rb job laptop_backup_job.yml my-bucket brian

Description
-----------

`aws_bucket` is a string like `my-s3-bucket`

`aws_profile` is a profile name in `~/.aws/credentials` See [Setting up AWS Credentials](http://docs.aws.amazon.com/AWSSdkDocsRuby/latest/DeveloperGuide/set-up-creds.html)

`backup_job_s3_key` is the name (s3_key) of a YAML file in aws_bucket that looks like this:

Job Configuration (YAML file)
-----------------------------
Here is an example `laptop_backup_job.yml` job file:

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
If you don't want to strip anything off, you must include just a `/` (forward slash),
you can't leave it blank.

`backup_folder_excludes` is an array of absolute paths to exclude from the backup_folder.
