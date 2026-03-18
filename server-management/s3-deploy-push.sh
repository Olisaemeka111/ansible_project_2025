#!/bin/bash

################################################################################
# S3 Code Push Script
# Purpose: Quickly archive and upload Ansible code to S3
# Usage: bash s3-deploy-push.sh [bucket-name]
################################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  S3 Code Push - Archive & Upload to S3${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# Get bucket name
BUCKET="${1}"

if [ -z "$BUCKET" ]; then
    echo -e "${BLUE}No bucket name provided.${NC}"
    echo ""
    echo "Options:"
    echo "  1. Create new bucket:"
    echo "     BUCKET=\"vprofile-ansible-\$(date +%s)\""
    echo "     aws s3 mb s3://\$BUCKET --region us-east-2"
    echo ""
    echo "  2. Use existing bucket:"
    echo "     bash s3-deploy-push.sh my-existing-bucket"
    echo ""
    echo "Creating new bucket..."
    BUCKET="vprofile-ansible-$(date +%s)"
    aws s3 mb s3://$BUCKET --region us-east-2
    echo -e "${GREEN}✓ Created bucket: $BUCKET${NC}"
fi

echo -e "${BLUE}Bucket: $BUCKET${NC}"
echo ""

# Check if bucket exists
if ! aws s3api head-bucket --bucket "$BUCKET" --region us-east-2 2>/dev/null; then
    echo -e "${RED}Error: Bucket '$BUCKET' not found or not accessible${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Bucket accessible${NC}"
echo ""

# Find parent directory (Ansible-infrastructure parent)
echo -e "${BLUE}Locating Ansible-infrastructure directory...${NC}"

# Try multiple locations
if [ -d "./Ansible-infrastructure" ]; then
    ANSIBLE_DIR="./Ansible-infrastructure"
elif [ -d "../Ansible-infrastructure" ]; then
    ANSIBLE_DIR="../Ansible-infrastructure"
elif [ -d "../../Ansible-infrastructure" ]; then
    ANSIBLE_DIR="../../Ansible-infrastructure"
else
    echo -e "${RED}Error: Cannot find Ansible-infrastructure directory${NC}"
    echo "Please run this script from:"
    echo "  • Ansible-infrastructure/server-management/ (current location)"
    echo "  • Ansible-infrastructure/"
    echo "  • Parent of Ansible-infrastructure/"
    exit 1
fi

echo -e "${GREEN}✓ Found: $ANSIBLE_DIR${NC}"
echo ""

# Create archive
echo -e "${BLUE}Creating archive...${NC}"
ARCHIVE="ansible-code-$(date +%Y%m%d_%H%M%S).tar.gz"

cd "$(dirname "$ANSIBLE_DIR")"
tar -czf "$ARCHIVE" "$(basename "$ANSIBLE_DIR")" --exclude=logs --exclude=reports --exclude=.git
ARCHIVE_SIZE=$(du -h "$ARCHIVE" | cut -f1)

echo -e "${GREEN}✓ Created: $ARCHIVE ($ARCHIVE_SIZE)${NC}"
echo ""

# Upload to S3
echo -e "${BLUE}Uploading to S3...${NC}"
aws s3 cp "$ARCHIVE" "s3://$BUCKET/" --region us-east-2

echo -e "${GREEN}✓ Uploaded to: s3://$BUCKET/$ARCHIVE${NC}"
echo ""

# Create symlink for easy reference
echo -e "${BLUE}Creating easy-access symlink...${NC}"
aws s3 cp "s3://$BUCKET/$ARCHIVE" "s3://$BUCKET/ansible-code.tar.gz" --region us-east-2 --copy-source "$BUCKET/$ARCHIVE"

echo -e "${GREEN}✓ Created symlink: s3://$BUCKET/ansible-code.tar.gz${NC}"
echo ""

# Summary
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  UPLOAD SUCCESSFUL! ✓${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}S3 Bucket:${NC} $BUCKET"
echo -e "${BLUE}File:${NC} ansible-code.tar.gz"
echo -e "${BLUE}Size:${NC} $ARCHIVE_SIZE"
echo ""

# Show next steps
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Save bucket name for control node setup:"
echo "   ${GREEN}echo '$BUCKET' > ~/s3_bucket.txt${NC}"
echo ""
echo "2. Launch EC2 control node with IAM role"
echo "3. Run bootstrap script:"
echo "   ${GREEN}bash bootstrap-control-node.sh $BUCKET us-east-2${NC}"
echo ""
echo "4. Deploy infrastructure:"
echo "   ${GREEN}./deploy.sh deploy${NC}"
echo ""

# Option to copy commands to clipboard (macOS)
if command -v pbcopy &> /dev/null; then
    echo "To copy bucket name to clipboard:"
    echo "   ${GREEN}echo '$BUCKET' | pbcopy${NC}"
fi

echo ""
echo "Documentation: See CONTROL_NODE_QUICK_START.md"
echo ""
