# Use the official image as a parent image.
FROM httpd:2.4.51

USER root
WORKDIR /root

# Set environment variables
ARG MYSQL_ROOT_PASSWORD
ENV DEVELOPER_MODE=TRUE
ENV MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"

# Download required packages for set-up
RUN apt-get update && apt-get install -y curl ca-certificates libapr1-dev libaprutil1-dev build-essential iputils-ping openssh-client sudo

# Set up daemon user
RUN mkdir /home/daemon
RUN chown -R daemon:daemon /home/daemon
RUN usermod daemon --home /home/daemon
WORKDIR /home/daemon
USER daemon

# Download and install miniconda
RUN curl https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh > Miniconda3-latest-Linux-x86_64.sh
RUN bash Miniconda3-latest-Linux-x86_64.sh -b -p /home/daemon/miniconda

# Copy project to image
COPY --chown=daemon:daemon . ./MAS

# Create mas conda environment
RUN /home/daemon/miniconda/bin/conda env create --file /home/daemon/MAS/container_setup_files/mas-environment.yml
RUN /home/daemon/miniconda/bin/conda init
RUN /home/daemon/miniconda/bin/conda clean -a -y

# Generate Secret Key
RUN cat /proc/sys/kernel/random/entropy_avail
RUN /home/daemon/miniconda/envs/mas/bin/python -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())' > /home/daemon/MAS/MAS/settings_files/secret_key.txt

# Collect static files
WORKDIR /home/daemon/MAS
RUN mkdir static-files
RUN /home/daemon/miniconda/envs/mas/bin/python manage.py collectstatic --noinput

# Create Terminase blast database
RUN /home/daemon/miniconda/envs/mas/bin/makeblastdb -dbtype prot -in /home/daemon/MAS/databases/terminase/phage_terminases.fasta -input_type fasta -title "Terminase Database" -out /home/daemon/MAS/databases/terminase/terminase_db

# Download PDB chain info. It will be loaded into django db on MAS container start-up.
RUN curl ftp://ftp.wwpdb.org/pub/pdb/derived_data/pdb_seqres.txt.gz > pdb_seqres.txt.gz
RUN gzip -d pdb_seqres.txt.gz

# Create directory for luigi logs
RUN mkdir luigi_logs

USER root

RUN /home/daemon/miniconda/envs/mas/bin/mod_wsgi-express install-module --modules-directory /usr/local/apache2/modules

RUN mv /usr/local/apache2/modules/mod_wsgi-py38.cpython-38-x86_64-linux-gnu.so /usr/local/apache2/modules/mod_wsgi.so

COPY container_setup_files/httpd.conf /usr/local/apache2/conf/httpd.conf

COPY container_setup_files/httpd-foreground /usr/local/bin/httpd-foreground

RUN touch /home/daemon/pidfile.pid
RUN touch /home/daemon/logfile.log