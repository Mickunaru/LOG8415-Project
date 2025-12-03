cd terraform
terraform destroy -auto-approve

cd ..
if [ -d "logs" ]; then
    echo "Removing local logs directory"
    rm -rf logs
fi

echo "Teardown completed"