# Developer documentation

This document explains how to set up the project from scratch, how it is built and launched, how to manage the containers and volumes, and where the data lives.

## Setting up the environment

### Prerequisites

- A Linux virtual machine (developed on Ubuntu)
- Docker Engine with the Docker Compose plugin (`docker compose version` should work)
- make, git and openssl
- sudo rights, used by the Makefile to edit `/etc/hosts` and by `make fclean` to delete data owned by the containers

Add your user to the `docker` group so Docker can be used without sudo, then log out and back in:

```bash
sudo usermod -aG docker $USER
```

### Project structure

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/                     # not in Git, created by hand
└── srcs/
    ├── compose.yaml
    ├── .env                     # not in Git, created by hand
    └── requirements/
        ├── nginx/
        │   ├── Dockerfile
        │   └── conf/nginx.conf
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── conf/www.conf
        │   └── tools/setup.sh
        └── mariadb/
            ├── Dockerfile
            ├── conf/50-server.cnf
            └── tools/setup.sh
```

`secrets/` and `srcs/.env` are listed in `.gitignore`, so after cloning the repository they have to be created.

### Configuration file

Create `srcs/.env` with the non-sensitive settings:

```
MYSQL_DATABASE=wordpress
MYSQL_USER=<db_user>

DOMAIN_NAME=wivallee.42.fr
WP_TITLE=<site title>
WP_ADMIN_USER=<admin name>
WP_ADMIN_EMAIL=<admin email>
WP_USER=<second user name>
WP_USER_EMAIL=<second user email>
```

`DOMAIN_NAME` is used as the nginx certificate's name (passed as a build argument) and as the WordPress site URL. Passwords never go in this file.

### Secrets

Each password is stored in its own file in `secrets/`. The easiest way is to generate random ones:

```bash
mkdir -p secrets
openssl rand -hex 16 > secrets/db_password.txt
openssl rand -hex 16 > secrets/db_root_password.txt
openssl rand -hex 16 > secrets/wp_admin_password.txt
openssl rand -hex 16 > secrets/wp_user_password.txt
chmod 600 secrets/*.txt
```

They are declared at the bottom of `srcs/compose.yaml` and granted only to the services that need them. Docker mounts them read-only in the containers at `/run/secrets/<name>`, and the setup scripts read them into local shell variables, so they never appear in the containers' environment or in the images:

| Secret | mariadb | wordpress | nginx |
|---|---|---|---|
| `db_password` | yes | yes | no |
| `db_root_password` | yes | no | no |
| `wp_admin_password` | no | yes | no |
| `wp_user_password` | no | yes | no |

The Makefile refuses to start if one of these files is missing or empty.

## Building and launching

### With the Makefile

```bash
make
```

This runs the following steps:

1. checks that `srcs/compose.yaml`, `srcs/.env` and the secret files exist
2. creates `/home/wivallee/data/wordpress` and `/home/wivallee/data/mariadb` if needed
3. adds the domain to `/etc/hosts` if it is not there yet
4. runs `docker compose -f srcs/compose.yaml up -d --build`

All Makefile targets:

| Target | What it does |
|---|---|
| `make` / `make up` | Build the images and start the containers |
| `make build` | Only build the images |
| `make down` | Stop and remove the containers and the network, data is kept |
| `make stop` / `make start` | Stop or start the existing containers |
| `make restart` | Restart the containers |
| `make ps` | Show the containers' status |
| `make logs` | Follow the logs of all services |
| `make clean` | Also remove the volume records and the built images, data on disk is kept |
| `make fclean` | Also delete the data folders and Docker's unused images and build cache |
| `make re` | `fclean` then `all`, a full reinstall |

### What happens on startup

Compose starts the services in this order:

1. **mariadb** runs its setup script. If the data directory is empty, it initialises it, creates the WordPress database and user, sets the root password and removes anonymous users, using a temporary server with networking disabled. It then starts `mariadbd` in the foreground. Its healthcheck runs `mariadb-admin ping` every 5 seconds.
2. **wordpress** waits until mariadb is healthy. Its setup script then downloads WordPress, creates `wp-config.php`, installs the site and creates the two users with WP-CLI. Each step is skipped if it was already done, so the script can safely run again after a failure. It ends with `exec php-fpm8.2 -F`.
3. **nginx** starts once wordpress is up, and forwards PHP requests to `wordpress:9000` over FastCGI.

Every container runs its main program in the foreground as PID 1, and restarts automatically unless it was stopped on purpose.

### Rebuilding after a change

Images are only rebuilt when asked. After editing a Dockerfile or any file it copies (configuration files, setup scripts), run `make` again, which always passes `--build`. To rebuild a single service:

```bash
docker compose -f srcs/compose.yaml up -d --build nginx
```

Changes to `compose.yaml` or `.env` are applied by recreating the containers, which `make` also does.

Values used during the first installation (database name, users, passwords, site URL) are stored in the volumes. Changing them in `.env` or `secrets/` later has no effect until the data is reset with `make re`.

## Managing containers and volumes

Useful Docker Compose commands, from the repository root:

```bash
docker compose -f srcs/compose.yaml ps -a              # status, including stopped containers
docker compose -f srcs/compose.yaml logs -f wordpress  # logs of one service
docker compose -f srcs/compose.yaml exec nginx bash    # shell inside a container
docker compose -f srcs/compose.yaml restart mariadb    # restart one service
docker compose -f srcs/compose.yaml config             # validate compose.yaml and show the result
```

Debugging inside the containers:

```bash
docker exec nginx nginx -T                                 # full nginx configuration in use
docker exec wordpress wp user list --allow-root            # WordPress users
docker exec wordpress wp option get home --allow-root      # site URL stored by WordPress
docker exec mariadb sh -c 'mariadb -u root -p"$(cat /run/secrets/db_root_password)"'   # database shell as root
```

Volumes and networks:

```bash
docker volume ls                                # inception_wp_files and inception_db_data
docker volume inspect inception_db_data         # shows the host folder used by the volume
docker network inspect inception_backend        # containers connected to the network
```

## Where the data is stored and how it persists

The project uses two named volumes, declared in `srcs/compose.yaml`:

| Volume | Mounted in | Used by | Host folder |
|---|---|---|---|
| `wp_files` | `/var/www/html` | wordpress (read and write), nginx (read only) | `/home/wivallee/data/wordpress` |
| `db_data` | `/var/lib/mysql` | mariadb | `/home/wivallee/data/mariadb` |

They are named volumes managed by Docker, but their `driver_opts` store the data in `/home/wivallee/data` on the host. These folders must exist before the volumes are created, which the Makefile takes care of.

Because the data lives outside the containers, it survives `make down`, `make stop`, rebuilding the images, and even `make clean`. On the next start, the setup scripts find the existing data and skip the installation steps. Only `make fclean` (or `make re`) deletes the folders' contents.

The files in these folders belong to the users inside the containers (`mysql` for the database, `www-data` for WordPress), which is why deleting them requires sudo.

Docker remembers the settings a volume was created with. If the host path in `compose.yaml` is changed, the old volume must be removed first (`make clean`, or `docker volume rm inception_db_data inception_wp_files` after `make down`), otherwise Docker keeps using the old path.
