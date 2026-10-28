# **************************************************************************** #
#                                  INCEPTION                                   #
# **************************************************************************** #

# Paths: DATA must match the "device:" paths in srcs/compose.yaml
COMPOSE_FILE	= srcs/docker-compose.yaml
ENV_FILE		= srcs/.env
DATA			= /home/wivallee/data

COMPOSE			= docker compose -f $(COMPOSE_FILE)
DOMAIN			= $(shell grep '^DOMAIN_NAME=' $(ENV_FILE) | cut -d= -f2)

# **************************************************************************** #
#                                   TARGETS                                    #
# **************************************************************************** #

all: up

# Check that the required files exist before doing anything
check:
	@test -f $(COMPOSE_FILE) || (echo "Missing $(COMPOSE_FILE)" && exit 1)
	@test -f $(ENV_FILE) || (echo "Missing $(ENV_FILE)" && exit 1)

# Create the host folders used by the named volumes
dirs:
	@mkdir -p $(DATA)/wordpress $(DATA)/mariadb

# Add the domain to /etc/hosts if it is not already there
hosts: check
	@grep -q "$(DOMAIN)" /etc/hosts || \
		(echo "127.0.0.1 $(DOMAIN)" | sudo tee -a /etc/hosts > /dev/null && \
		echo "Added $(DOMAIN) to /etc/hosts")

# Build images and start every container in the background
up: check dirs hosts
	$(COMPOSE) up -d --build

# Only build the images
build: check
	$(COMPOSE) build

# Stop and remove containers and the network (data is kept)
down:
	$(COMPOSE) down

# Stop containers without removing them
stop:
	$(COMPOSE) stop

# Start containers that were stopped
start:
	$(COMPOSE) start

# Restart every container
restart:
	$(COMPOSE) restart

# Show the status of the containers
ps:
	$(COMPOSE) ps -a

# Follow the logs of every service (Ctrl+C to quit)
logs:
	$(COMPOSE) logs -f

# Remove containers, network, volume records and built images (data is kept)
clean:
	$(COMPOSE) down -v --rmi all

# Everything clean does, plus delete the data and Docker's unused cache
fclean: clean
	sudo rm -rf $(DATA)/wordpress $(DATA)/mariadb
	docker system prune -af

# Full reset and reinstall
re: fclean all

.PHONY: all check dirs hosts up build down stop start restart ps logs clean fclean re
