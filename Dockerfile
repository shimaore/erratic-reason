FROM node:alpine as builder

WORKDIR /home/node/app
COPY . ./

RUN npm run build && rm -rf node_modules

RUN npm install && \
    npm cache clean -f

RUN apk add --no-cache tini
USER node
ENTRYPOINT ["/sbin/tini","--","node","server.js"]
