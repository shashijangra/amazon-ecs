AWS_REGION = "us-east-1"
REPO_URL = "https://github.com/mransbro/python-api"
ECR_URL = 738510716085.dkr.ecr.us-east-1.amazonaws.com/flask-api
ECS_CLUSTER = "ecs-cluster"
ECS_SERVICE = "flask_api_service"

# Get Git revision
GIT_REVISION = $(shell git rev-parse --short HEAD)

clone:
	git clone $(REPO_URL)

login:
	aws configure

docker-build:
	docker build -t $(ECR_URL):$(GIT_REVISION) -f ./python-api/Dockerfile ./python-api/

docker-push:
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_URL)
	docker push $(ECR_URL):$(GIT_REVISION)
	sed -i -e "s/IMAGE_TAG/$(GIT_REVISION)/g" task-def.json

update-task:
	aws ecs register-task-definition --region $(AWS_REGION) --cli-input-json file://task-def.json --query 'taskDefinition.taskDefinitionArn'

refresh-svc:
	aws ecs update-service --region $(AWS_REGION)  --cluster $(ECS_CLUSTER) --service $(ECS_SERVICE) --task-definition flask-api-task 

wait-service:
	aws ecs wait services-stable \
	  --region $(AWS_REGION) \
	  --cluster $(ECS_CLUSTER) \
	  --services $(ECS_SERVICE)

get-task-status:
	aws ecs describe-tasks \
	  --region $(AWS_REGION) \
	  --cluster $(ECS_CLUSTER) \
	  --tasks $(shell aws ecs list-tasks --region $(AWS_REGION) --cluster $(ECS_CLUSTER) --service-name $(ECS_SERVICE) --query 'taskArns[0]' --output text) \
	  --query 'tasks[0].lastStatus'


build: docker-build docker-push

deploy: update-task refresh-svc wait-service wait-service get-task-status