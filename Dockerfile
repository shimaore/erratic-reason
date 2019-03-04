FROM node:alpine as builder

WORKDIR /home/node/app
COPY . ./

RUN npm install && \
    npm run build && \
    npm cache clean -f

RUN apk add --no-cache tini
USER node
ENTRYPOINT ["/sbin/tini","--","node","server.js"]
