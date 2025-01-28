#!/bin/bash
# Update the package list and install updates
sudo apt-get update -y

# Install Python and pip
sudo apt-get install -y python3 python3-pip python3-venv

# Create a virtual environment
python3 -m venv /home/ubuntu/venv

# Activate the virtual environment
source /home/ubuntu/venv/bin/activate

# Install required Python packages within the virtual environment
/home/ubuntu/venv/bin/pip install boto3==1.28.0 botocore==1.31.0

# Install Ansible within the virtual environment
/home/ubuntu/venv/bin/pip install ansible

# Check the Python and Ansible versions within the virtual environment
/home/ubuntu/venv/bin/python --version
/home/ubuntu/venv/bin/ansible --version

# Additional package installations can be added here