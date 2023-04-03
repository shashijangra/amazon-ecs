# =========================      VPC 

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "api-vpc"
  }
}

resource "aws_subnet" "subnet-1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  depends_on = [
    aws_vpc.vpc
  ]
}

resource "aws_subnet" "subnet-2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  depends_on = [
    aws_vpc.vpc
  ]
}

resource "aws_security_group" "sg" {
  name_prefix = "api-vpc-sg"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = [
    aws_vpc.vpc
  ]
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  depends_on = [
    aws_vpc.vpc, aws_subnet.subnet-1, aws_subnet.subnet-1
  ]
}

resource "aws_route_table" "second_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

}

resource "aws_route_table_association" "subnet1_asso" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.second_rt.id
}

resource "aws_route_table_association" "subnet2_asso" {
  subnet_id      = aws_subnet.subnet-2.id
  route_table_id = aws_route_table.second_rt.id
}


# =========================      Load Balancer

resource "aws_lb" "flask_api_lb" {
  name               = "flask-api-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg.id]
  subnets            = [aws_subnet.subnet-1.id, aws_subnet.subnet-2.id]
}

resource "aws_lb_target_group" "flask_api_target_group" {
  name        = "flask-api-target"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"

  depends_on = [
    aws_lb.flask_api_lb
  ]
}

resource "aws_lb_listener" "flask_api_listener" {
  load_balancer_arn = aws_lb.flask_api_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.flask_api_target_group.arn
    type             = "forward"
  }
  depends_on = [
    aws_lb_target_group.flask_api_target_group
  ]
}

# =========================      ECR

resource "aws_ecr_repository" "ecr" {
  name                 = "flask-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}


# =========================      ECS

resource "aws_ecs_cluster" "ecs-cluster" {
  name = "ecs-cluster"
}

# =========================      Task Defination

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecr-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}


resource "aws_ecs_task_definition" "flask_api_task" {
  family = "flask-api-task"
  container_definitions = jsonencode([
    {
      name  = "flask-api-container"
      image = "${aws_ecr_repository.ecr.repository_url}:latest"
      portMappings = [
        {
          name          = "flask-api-80-tcp"
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
          appProtocol   = "http"
        },
        {
          name          = "flask-api-5000-tcp"
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
    }
  ])

  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "3072"
  network_mode             = "awsvpc"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  depends_on = [
    aws_ecs_cluster.ecs-cluster
  ]
}


resource "aws_ecs_service" "flask_api_service" {
  name            = "flask_api_service"
  cluster         = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.flask_api_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.flask_api_target_group.arn
    container_name   = "flask-api-container"
    container_port   = 5000
  }


  network_configuration {
    security_groups  = [aws_security_group.sg.id]
    subnets          = [aws_subnet.subnet-1.id, aws_subnet.subnet-2.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_lb.flask_api_lb
  ]
}
