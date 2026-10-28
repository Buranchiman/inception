*This project has been created as part of the 42 curriculum by wivallee.*

## Description

Inception is a system administration project from the 42 curriculum. The goal is to learn how Docker and containerisation work by building a small web infrastructure from scratch: a WordPress website, served over HTTPS by nginx and backed by a MariaDB database.

Each service runs in its own container, built from my own Dockerfiles. No ready-made images from Docker Hub are used apart from the Debian base image, so everything (installing nginx, PHP-FPM and MariaDB, configuring them and setting up WordPress) is done by hand inside the images and their startup scripts. The whole stack is described in a single compose file and started with one `make` command.

## Project description

### How it works

When someone opens `https://wivallee.42.fr`, the request reaches the nginx container on port 443, which is the only port opened to the outside. nginx handles the TLS encryption (TLSv1.2 and TLSv1.3 only, with a self-signed certificate generated during the build) and serves static files like images and CSS directly. Requests for PHP files are forwarded with FastCGI to the WordPress container, where PHP-FPM listens on port 9000. WordPress then reads and writes its content in the MariaDB container on port 3306.

WordPress and MariaDB are not reachable from the host at all. They only exist on the internal Docker network, which means the database can never be accessed directly from outside.

### Sources included in the project

```
.
├── Makefile
├── secrets/                  # passwords, one file per secret (not pushed to Git)
└── srcs/
    ├── compose.yaml
    ├── .env                  # non-sensitive settings (not pushed to Git)
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

- **nginx**: installs nginx and openssl, generates the certificate for the domain passed as a build argument, and runs nginx in the foreground with `daemon off;`.
- **wordpress**: installs PHP 8.2 with FPM and the extensions WordPress needs, plus WP-CLI. On the first start, `setup.sh` downloads WordPress, creates `wp-config.php`, installs the site and creates two users (an administrator and an author). Every step checks whether it was already done, so the script can be restarted safely. It then replaces itself with `php-fpm8.2 -F`.
- **mariadb**: installs MariaDB and changes its configuration so it listens on the Docker network instead of only on localhost. On the first start, `setup.sh` initialises the data directory, creates the WordPress database and user, sets the root password and removes anonymous users, then starts `mariadbd` in the foreground. A healthcheck makes WordPress wait until the database is actually ready.

### Main design choices

I chose **Debian bookworm** (the penultimate stable version) as the base for all three images. Alpine would give smaller images, but Debian behaves like the Ubuntu VM I work on, with the same package manager and paths, which made debugging a lot easier.

Every container runs its real program as its main process (PID 1) instead of a background daemon kept alive with something like `tail -f`. The setup scripts end with `exec`, so nginx, PHP-FPM and MariaDB receive Docker's stop signals directly and shut down cleanly. Containers restart automatically if they crash.

Configuration is split in two: names, emails and the domain are in `srcs/.env`, while passwords are in separate files in `secrets/`. Only the containers that need a secret get it.

### Virtual Machines vs Docker

A virtual machine emulates a whole computer with its own operating system and kernel, so it is heavy, takes a while to boot and uses a fixed amount of RAM and disk. A Docker container shares the kernel of the host and only isolates the processes, files and network of one application. That makes containers much lighter and faster to start, and you can run many of them on the same machine. The trade-off is that the isolation is weaker than with a VM, since everything runs on the same kernel. In this project I use both: the VM gives me a clean Linux environment, and inside it each service runs in its own container.

### Secrets vs Environment Variables

Environment variables are easy to use, but they are visible to anyone who can run `docker inspect` or `env` inside the container, they are passed to every process, and with an `env_file` every service receives all of them. Docker secrets are mounted as read-only files in `/run/secrets/`, only in the containers they are granted to. In my setup, nginx gets no secret at all, MariaDB gets the database passwords, and WordPress only gets the ones it uses. The setup scripts read the files into local shell variables, so the passwords never appear in the container's environment. Secrets are still plain files on the host, so they are kept out of Git with `.gitignore`.

### Docker Network vs Host Network

With the host network, a container uses the network of the host directly: no isolation, and every port it opens is open on the machine. With a Docker bridge network, the containers get their own private network where they can reach each other by service name (`wordpress:9000`, `mariadb:3306`), and nothing is reachable from the outside unless a port is explicitly published. This project uses a bridge network called `backend`, and only port 443 of nginx is published, which is exactly what makes nginx the single entry point.

### Docker Volumes vs Bind Mounts

A bind mount maps a precise folder of the host into a container. It is simple and handy during development, but it depends on the host's folder structure and permissions. A named volume is created and managed by Docker: it has a name, shows up in `docker volume ls`, and is independent from where the container runs. The project uses two named volumes, `wp_files` for the WordPress files (shared between nginx and WordPress) and `db_data` for the database. As required, their data is stored in `/home/wivallee/data` on the host, using the local driver options. Volumes are what keep the site and database alive when the containers are removed and recreated.

## Instructions

### Requirements

- A Linux virtual machine (I used Ubuntu)
- Docker and the Docker Compose plugin, with your user in the `docker` group
- make
- sudo rights (the Makefile adds the domain to `/etc/hosts`, and `make fclean` deletes data owned by the containers)

### Setup

The `.env` file and the `secrets/` folder are not in the repository, so they have to be created first.

`srcs/.env`:

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

`secrets/`, one password per file:

```bash
mkdir -p secrets
echo 'password' > secrets/db_password.txt
echo 'password' > secrets/db_root_password.txt
echo 'password' > secrets/wp_admin_password.txt
echo 'password' > secrets/wp_user_password.txt
chmod 600 secrets/*.txt
```

### Running the project

```bash
make
```

This creates the data folders in `/home/wivallee/data`, adds `wivallee.42.fr` to `/etc/hosts` if it is not there yet, builds the three images and starts the containers. The first start takes a little longer because WordPress is downloaded and installed.

Then open `https://wivallee.42.fr` in a browser on the VM. The certificate is self-signed, so the browser shows a warning that has to be accepted. The admin panel is at `https://wivallee.42.fr/wp-admin`.

Other useful commands:

- `make down` stops and removes the containers, the data is kept
- `make stop` / `make start` / `make restart` pause, resume or restart the containers
- `make ps` shows the containers' status, `make logs` follows their logs
- `make clean` also removes the volumes' records and the images, the data on disk is kept
- `make fclean` deletes everything, including the data and Docker's cache
- `make re` does a full reset and reinstall

Note that the users and passwords are only applied the first time the database and WordPress are installed. If they are changed afterwards, a `make re` is needed for them to be taken into account.

## Resources

- Docker documentation: https://docs.docker.com/
- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Compose file reference: https://docs.docker.com/reference/compose-file/
- Using secrets in Compose: https://docs.docker.com/compose/how-tos/use-secrets/
- nginx documentation: https://nginx.org/en/docs/
- PHP-FPM: https://www.php.net/manual/en/install.fpm.php
- WordPress documentation: https://wordpress.org/documentation/
- WP-CLI: https://wp-cli.org/
- MariaDB documentation: https://mariadb.com/docs/
- Mozilla SSL configuration generator, for TLS settings: https://ssl-config.mozilla.org/

### Use of AI

I used Claude as a learning assistant throughout the project. I started with no knowledge of Docker, nginx, PHP or WordPress, so I mostly used it to explain concepts: images vs containers, what happens at build time vs run time, port mapping, daemons and why containers need a foreground process, YAML and Compose syntax, TLS and certificates, how nginx and PHP-FPM communicate, and how volumes hide what is already in a folder. It also helped me with the structure and wording of this README.
