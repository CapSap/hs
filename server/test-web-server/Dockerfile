FROM node:20-alpine 
WORKDIR /app

RUN apk add --no-cache git && \
    git clone https://github.com/CapSap/norm-tribute.git . && \
    rm -rf .git

# Install dependencies 
RUN npm install

# Expose the port your server listens on
EXPOSE 3001

# Start the server
CMD ["node", "index.js"]