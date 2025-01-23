#!/bin/bash
# Update the package list and install updates
sudo apt-get update -y

# Install Python and pip
sudo apt-get install -y python3 python3-pip

# Install required Python packages
pip3 install boto3==1.28.0 botocore==1.31.0

# Additional package installations can be added here