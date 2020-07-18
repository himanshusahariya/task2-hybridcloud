# Declaring Provider
provider "aws" {
  region = "ap-south-1"
 // your profile for AWS here.
 profile = "honey"   
}


# Creating Key Pair
resource "tls_private_key" "webserver_key"  {
    algorithm = "RSA"
    rsa_bits =   4096
}


# Creating a file for key on local system.
resource "local_file" "private_key" {
  depends_on = [
    tls_private_key.webserver_key,
  ]
  content = tls_private_key.webserver_key.private_key_pem
  filename = "Task2-key.pem"
  file_permission = 0777
}


resource "aws_key_pair" "webserver_key"{
  key_name = "mynewkey"
  public_key = tls_private_key.webserver_key.public_key_openssh
}

# Creating Security Group
resource "aws_security_group" "allow_traffic" {
  name        = "allowed_traffic"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}


# Creating Security Group for NFS server
resource "aws_security_group" "allow_nfs" {
  name        = "NFS_security"
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}


// NFS File system creation 
resource "aws_efs_file_system" "my_file_system" {
// unique file system name here.
  creation_token = "myuniquefilesystem"           

  tags = {
    Name = "MyProduct"
  }
}


// mount target for EFS
resource "aws_efs_mount_target" "gamma" {
depends_on = [
    aws_efs_file_system.my_file_system,
    aws_security_group.allow_nfs,
    aws_instance.ins1,
  ]
  file_system_id  = aws_efs_file_system.my_file_system.id
  subnet_id       = aws_instance.ins1.subnet_id
  security_groups = [aws_security_group.allow_nfs.id]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host        = aws_instance.ins1.public_ip
  }
   
provisioner "remote-exec" {
    inline = [
      "sudo yum install amazon-efs-utils nfs-utils -y",
      "sudo chmod ugo+rw /etc/fstab",
      "sudo echo '${aws_efs_file_system.my_file_system.id}:/ /var/www/html efs tls,_netdev 0 0' >> /etc/fstab",
      "sudo mount -a -t efs,nfs4 defaults",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/himanshusahariya/test-repo.git /var/www/html",
    ]
 }
}


#Creation of instance is done in this block.
resource "aws_instance" "ins1"{
depends_on = [
    aws_key_pair.webserver_key,
    aws_security_group.allow_traffic,
  ]

  ami             = "ami-005956c5f0f757d37" 
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.webserver_key.key_name
  security_groups = [aws_security_group.allow_traffic.name]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host        = aws_instance.ins1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd git php -y",
      "sudo service httpd start",
    ]
  }
    tags = {
    Name = "teraOS"
 }
}


# Variable Declaration For bucket
variable "Unique_Bucket_Name"{
  type = string
  //default = "my-bucket-9521"
}


# AWS S3 Bucket Creation
resource "aws_s3_bucket" "my_bucket" {
  bucket = var.Unique_Bucket_Name
  acl    = "public-read"
  
  provisioner "local-exec" {
    when = destroy 
    command = "echo y | rmdir /s test-repo"
  }
}


# Saving name of the bucket to local system
resource "null_resource" "null2" {
  depends_on = [
      aws_s3_bucket.my_bucket,
]
  provisioner "local-exec" {
    command = "echo ${aws_s3_bucket.my_bucket.bucket} > bucket_name.txt"
  } 
}


# Cloning git repository to local system
resource "null_resource" "null" {
  provisioner "local-exec" {
// Provide github repo link here after gitclone to provide your webserver code.
    command = "git clone https://github.com/himanshusahariya/test-repo.git"
  } 
}


# Upload image file on S3 storage from github repository at local system
resource "aws_s3_bucket_object" "object1" {
  depends_on =[
      null_resource.null,
      aws_s3_bucket.my_bucket
]
  bucket = aws_s3_bucket.my_bucket.bucket
  key    = "bucket_image.jpg"
// Provide path here according To your system's file system
  source = "H:/Hybrid Cloud/terraform/EFS-Task2/test-repo/images/Terraform-main-image.jpg"
  acl    = "public-read"
} 


# Cloudfront Distribution Creation
resource "aws_cloudfront_distribution" "s3_distribution" { 
  origin {
    domain_name = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.my_bucket.bucket
  }
  enabled = true
    default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.my_bucket.bucket
  forwarded_values {
      query_string = false
        cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
output "cloudfront"{
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}


# Copying object link from cloudfront distribution to webserver file 
resource "null_resource" "nulll" {
  depends_on = [
      aws_cloudfront_distribution.s3_distribution,   
      aws_efs_mount_target.gamma,
]
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host        = aws_instance.ins1.public_ip
  }
  provisioner "remote-exec" {
      inline = [ 
        # sudo su << \"EOF\" \n echo \"<img src='${aws_cloudfront_distribution.s3_distribution.domain_name}'>\" >> /var/www/html/test1.php \n \"EOF\"
            "sudo su << EOF",
         "echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object1.key}'>\" >> /var/www/html/test1.php",
          "EOF"
     ]
  }
}


# Copying Webserver link to local system
resource "null_resource" "link" {
     depends_on =[
          aws_instance.ins1,
]
  provisioner "local-exec" {
    command = "echo 'http://${aws_instance.ins1.public_ip}/test1.php' > Link_To_Webpage.txt"
  } 
} 

/* 
"sudo mount ${aws_efs_file_system.my_file_system.id}:/  /var/www/html",
      "sudo echo '${aws_efs_file_system.my_file_system.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      */