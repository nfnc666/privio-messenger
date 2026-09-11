# The Privio server, as one image.
#
# Two stages, because the build needs TypeScript and the run does not: what
# ships is `dist/`, the production dependencies and nothing else — no compiler,
# no test suite, no source.
#
# `slim` rather than `alpine`: `@node-rs/argon2` is a native module, and Debian
# is the platform its prebuilt binaries are actually tested on. A password hash
# that falls back to a slow JavaScript implementation, or fails to load at all,
# is not a thing to discover in production.

# --- build -------------------------------------------------------------------
FROM node:22-slim AS build
WORKDIR /app

# The lockfile first, so a source change does not re-resolve every dependency.
COPY package.json package-lock.json ./
COPY server/package.json server/
RUN npm ci

COPY server/ server/
RUN npm --workspace server run build

# Only what the server needs at run time. `npm ci --omit=dev` re-resolves from
# the same lockfile, so the versions are the ones the build was checked with.
#
# npm hoists workspace dependencies to the root, so `server/node_modules` may
# not exist at all — and a `COPY` whose source is missing fails the build. The
# directory is created unconditionally so the run stage copies the same two
# paths whether or not npm decided a nested install was necessary.
RUN npm ci --omit=dev && mkdir -p /app/server/node_modules

# --- run ---------------------------------------------------------------------
FROM node:22-slim AS run
WORKDIR /app

ENV NODE_ENV=production
# Where attachments and backups are written. A platform mounts a volume here;
# without one they live in the container's own filesystem and are lost on the
# next deploy. The server says so at start-up rather than leaving it to be
# discovered by somebody whose backup is gone.
ENV MEDIA_DIR=/data/media

COPY --from=build /app/node_modules node_modules/
COPY --from=build /app/server/node_modules server/node_modules/
COPY --from=build /app/server/dist server/dist/
COPY --from=build /app/server/package.json server/
COPY --from=build /app/server/migrations server/migrations/
# The Privio mark, served on the invite pages and used as the link preview
# image. Not bundled by `tsc`, so it is copied beside `dist/` explicitly.
COPY --from=build /app/server/assets server/assets/

# `node` exists in the image already, and root is not needed to listen on 8080.
RUN mkdir -p /data/media && chown -R node:node /data
USER node

EXPOSE 8080

# Migrations run at start-up, inside the application, so there is no separate
# release step for a platform to forget.
CMD ["node", "server/dist/index.js"]
