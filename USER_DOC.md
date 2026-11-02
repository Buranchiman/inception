# User documentation

This document explains how to use the Inception stack once it is installed: what it runs, how to start and stop it, how to reach the website, where the credentials are, and how to check that everything works. All commands are run from the root of the repository, on the virtual machine.

## What the stack provides

The project runs a WordPress website made of three services, each in its own container:

- **nginx** is the web server and the only entry point. It listens on port 443 (HTTPS) and is the only service reachable from outside.
- **wordpress** runs WordPress with PHP-FPM. It generates the pages and is only reachable by nginx.
- **mariadb** is the database where WordPress stores its content (posts, users, settings). It is only reachable by WordPress.

The website's files and the database are stored on the host, so nothing is lost when the containers are stopped or rebuilt.

## Starting and stopping the project

Start everything:

```bash
make
```

The first start takes a bit longer because WordPress is downloaded and installed. After that, starting only takes a few seconds.

Stop everything:

```bash
make down
```

This removes the containers but keeps the website and the database. The next `make` brings everything back as it was.

Other useful commands:

- `make stop` and `make start` pause and resume the containers without removing them
- `make restart` restarts all the containers
- `make re` reinstalls everything from scratch (see the warning below)

**Warning:** `make fclean` and `make re` delete the website and the database, including every post, page and uploaded image. Only use them if you really want to start over.

## Accessing the website

Open a browser on the virtual machine and go to:

- **Website:** https://wivallee.42.fr
- **Administration panel:** https://wivallee.42.fr/wp-admin

The certificate is self-signed, so the browser shows a security warning the first time. This is expected: click "Advanced", then accept the risk and continue. The connection is still encrypted.

If the browser says "server not found", the domain is missing from `/etc/hosts`. Running `make` adds it automatically, or it can be added by hand:

```bash
echo "127.0.0.1 wivallee.42.fr" | sudo tee -a /etc/hosts
```

## Credentials

There are two kinds of accounts, and their information is stored in two places that are never pushed to Git.

**Usernames and emails** are in `srcs/.env`:

- `WP_ADMIN_USER`: the WordPress administrator, who can manage everything
- `WP_USER`: a second WordPress account with the author role, who can write and publish posts
- `MYSQL_USER`: the account WordPress uses to connect to the database

**Passwords** are in the `secrets/` folder, one file per password:

| File | Password of |
|---|---|
| `secrets/wp_admin_password.txt` | the WordPress administrator |
| `secrets/wp_user_password.txt` | the second WordPress user |
| `secrets/db_password.txt` | the database user |
| `secrets/db_root_password.txt` | the database root account |

To read a password, for example to log into the admin panel:

```bash
cat secrets/wp_admin_password.txt
```

These files are only readable by their owner. Do not share them and never commit them.

**Changing a password:** the values are only used when the site and database are first installed. Changing a file afterwards has no effect on its own. To apply new passwords, update the files and run `make re`, keeping in mind that this deletes the site's content. A WordPress password can also be changed from the admin panel (Users, then Profile) without reinstalling, but then remember to update the matching file so it stays accurate.

## Checking that everything works

**Container status:**

```bash
make ps
```

All three containers should show `Up`, and mariadb should show `(healthy)`. nginx should show `0.0.0.0:443->443/tcp` in the ports column.

**Logs**, to see what each service is doing or why it fails:

```bash
make logs
```

Press Ctrl+C to stop following them. On a normal start, WordPress ends with "Starting PHP-FPM..." and MariaDB with "ready for connections".

**Website response:**

```bash
curl -kI https://wivallee.42.fr
```

The first line should be `HTTP/1.1 200 OK`.

**Database**, by connecting with the WordPress database account:

```bash
docker exec mariadb sh -c 'mariadb -u "$MYSQL_USER" -p"$(cat /run/secrets/db_password)" -e "SHOW DATABASES;"'
```

The list should include `wordpress`.

**Common problems:**

- The page shows **502 Bad Gateway**: nginx is running but WordPress is not. Check `make logs` for errors from the wordpress container.
- The page shows **"Error establishing a database connection"**: WordPress cannot log into MariaDB, usually because a password in `secrets/` was changed after installation.
- A container keeps **restarting**: its logs explain why, for example a missing secret file or a configuration error.
