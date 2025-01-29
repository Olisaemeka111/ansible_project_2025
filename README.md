Here is a well-structured **README.md** file for your Ansible project. It provides detailed information about the project, its purpose, prerequisites, and instructions for running the playbook.

---

# **Ansible Project: Provisioning AWS EC2 Instances**

## **Project Overview**
This Ansible project automates the provisioning of AWS infrastructure, including setting up a Virtual Private Cloud (VPC), Subnets, Security Groups, and EC2 instances, to deploy and manage resources efficiently in the AWS cloud. The playbook uses the `amazon.aws` collection for AWS resource management.

**Key Features:**
- Creates a VPC and public subnet.
- Configures an Internet Gateway and Route Table.
- Creates a Security Group with custom rules.
- Launches EC2 instances in a specified AWS region.
- Dynamically adds created EC2 instances to the `ec2_hosts` Ansible group.

---

## **Folder Structure**

```
├── playbook.yml              # Main Ansible playbook.
├── ec2_2_vars.yml            # Variables file (contains user-defined values like region, instance type, etc.).
├── README.md                 # Documentation about the project.
├── requirements.yml          # Ansible collections required (e.g., amazon.aws).
```

---

## **Prerequisites**

### **1. AWS Account**
Ensure you have an AWS account with adequate permissions for EC2, VPC, and IAM operations.

### **2. AWS Access Keys**
You need AWS Access Key ID and Secret Access Key to authenticate with AWS. Keep these credentials secure.

### **3. Install Ansible**
Install Ansible on your local machine:
```shell script
pip install ansible
```

### **4. Ansible AWS Collection**
Install the `amazon.aws` collection for managing AWS resources:
```shell script
ansible-galaxy collection install amazon.aws
```

### **5. Configure AWS CLI (Optional)**
It's recommended to set up AWS CLI for seamless integration:
```shell script
aws configure
```

### **6. Python and Dependencies**
Install Python `boto3` and `botocore` libraries for Ansible AWS modules:
```shell script
pip install boto3 botocore
```

---

## **Variable Definitions**

The `ec2_2_vars.yml` file contains customizable variables. Below is an example:

```yaml
vpc_name: my_vpc               # Name of the VPC
vpc_cidr: 10.0.0.0/16          # CIDR block for the VPC
subnet_cidr: 10.0.1.0/24       # CIDR block for the subnet
aws_region: us-east-1          # AWS region
ami_id: ami-0123456789abcdef0  # AMI ID to use for EC2 instances
instance_type: t2.micro        # Instance type
key_name: my-key-pair          # Name of the SSH key pair
security_group: web-sg         # Security group name
```

Update these variables as per your AWS environment and requirements.

---

## **How to Run**

### **1. Clone the Repository**
Clone the repository to your local machine:
```shell script
git clone <repository-url>
cd <repository-folder>
```

### **2. Update Variable File**
Edit `ec2_2_vars.yml` and provide the relevant values (e.g., VPC name, region, AMI ID, etc.).

### **3. Run the Playbook**
Execute the playbook using the `ansible-playbook` command:
```shell script
ansible-playbook playbook.yml -e @ec2_2_vars.yml
```

### **4. Debugging (Optional)**
Enable verbose logging by adding the `-vvv` flag:
```shell script
ansible-playbook playbook.yml -e @ec2_2_vars.yml -vvv
```

---

## **What the Playbook Does**

1. **Creates a VPC**:
   - A new VPC with the specified name and CIDR block.

2. **Creates Network Resources**:
   - Public Subnet, Internet Gateway, and Route Table with proper associations.

3. **Security Group Configuration**:
   - Opens specified ports (e.g., SSH, HTTP, HTTPS).

4. **Launches EC2 Instances**:
   - Deploys EC2 instances within the configured VPC and subnet.

5. **Adds Hosts to Inventory**:
   - Dynamically adds public IP addresses of the instances to the `ec2_hosts` group.

---

## **Outputs**

- Public IP addresses and instance IDs of the created EC2 instances will be displayed and stored dynamically in the instance variable.
- Example output:
```shell script
TASK [debug] 
  ok: [localhost] => (item=0) => {
      "msg": "Created instance with ID: i-0a12b345c67d89e01, Public IP: 34.238.152.72, Name: webapp-instance-1"
  }
```

---

## **Important Notes**

1. **Key Pair**: Ensure the key pair specified in the `key_name` variable exists in the specified AWS region before running the playbook.
2. **Resource Cleanup**: Keep track of your AWS resources to avoid unnecessary charges. Delete resources manually after testing.
3. **Security**: Avoid exposing sensitive files, such as variables containing AWS credentials.

---

## **Troubleshooting**

### **Common Issues**
1. **Authentication Failure**: 
   Ensure your AWS credentials are correctly configured.
   
2. **Region-Specific Errors**:
   Make sure the AMI ID and instance type are valid in your selected `aws_region`.

3. **Permissions Issue**:
   Check if the AWS IAM user/role has necessary permissions for creating resources.

4. **CIDR Overlap**:
   Ensure the CIDR blocks do not overlap with other networks in the same AWS account or region.

---

## **Future Enhancements**

- Implement resource cleanup playbooks for automating infrastructure teardown.
- Add support for additional configurations, such as private subnets and NAT Gateways.
- Deploy applications on EC2 instances as part of the provisioning process.

---

## **Contributing**

Feel free to contribute to this project by creating a pull request. Suggestions for improvements are always welcome.

---

## **Author**

This project is maintained by Olisa Arinze].  
For any questions or feedback, feel free to contact at **[goad-nitrous-8w@icloud.com
](mailto:olisa.arinze@icloud.com)**.

--- 

This **README.md** follows good documentation practices, making your project easy to understand and use. Let me know if you would like to add more sections or details!
