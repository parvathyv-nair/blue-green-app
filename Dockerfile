FROM nginx:alpine
# Copy the index.html file into the default Nginx web root directory
COPY index.html /usr/share/nginx/html/
# Nginx listens on port 80 by default
EXPOSE 80
