import { randomBytes } from 'node:crypto';
import { pool } from '../db/pool.js';
import { migrate } from '../db/migrate.js';
import { ADMIN_ROLES, type AdminRole, createAdminUser, hasAnyAdmin } from '../services/admin_auth.js';

/**
 * Creates the first operator, from a shell on the server.
 *
 * There is no sign-up page for the admin panel and there will not be one: an
 * endpoint that mints the first operator is an endpoint that mints the first
 * operator for whoever reaches it first, and on a server that has just been
 * deployed and not yet configured, that is not necessarily the person who
 * deployed it. Shell access to the machine is the credential this trades on,
 * which is the same credential that could read the database anyway.
 *
 *   npm --workspace server run create-admin -- --username ada --role owner
 *
 * The password is generated and printed once unless one is supplied. Printed to
 * stdout rather than saved anywhere, and the process exits without writing it
 * to any file — including the shell history, which is why it is not an argument.
 * Supply one through `ADMIN_PASSWORD` if it has to come from somewhere else.
 *
 * Two-factor is not set up here, because there is no way to show a QR code to
 * somebody who is not logged in yet. The panel asks on first sign-in, and
 * `POST /v1/admin/me/totp/setup` is where it actually happens.
 */

interface Args {
  username: string;
  role: AdminRole;
  displayName?: string;
  /** Create an operator even though the table is not empty. */
  force: boolean;
}

function usage(message?: string): never {
  if (message) console.error(`error: ${message}\n`);
  console.error(
    `usage: npm --workspace server run create-admin -- --username <name> [options]

  --username <name>      3-32 chars of a-z, 0-9, dot, dash, underscore. Required.
  --role <role>          ${ADMIN_ROLES.join(' | ')}  (default: owner)
  --display-name <text>  Shown in the panel instead of the username.
  --force                Create even though operators already exist.

The password is read from ADMIN_PASSWORD, or generated and printed once.`,
  );
  process.exit(message ? 2 : 0);
}

function parseArgs(argv: string[]): Args {
  const args: Partial<Args> & { force: boolean } = { force: false };
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    const value = argv[i + 1];
    switch (flag) {
      case '--username':
        if (!value) usage('--username needs a value');
        args.username = value.trim().toLowerCase();
        i += 1;
        break;
      case '--role': {
        if (!value) usage('--role needs a value');
        if (!(ADMIN_ROLES as readonly string[]).includes(value)) {
          usage(`--role must be one of ${ADMIN_ROLES.join(', ')}`);
        }
        args.role = value as AdminRole;
        i += 1;
        break;
      }
      case '--display-name':
        if (!value) usage('--display-name needs a value');
        args.displayName = value;
        i += 1;
        break;
      case '--force':
        args.force = true;
        break;
      case '--help':
      case '-h':
        usage();
        break;
      default:
        usage(`unknown argument ${flag}`);
    }
  }
  if (!args.username) usage('--username is required');
  if (!/^[a-z0-9_.-]{3,32}$/.test(args.username)) {
    usage('--username must be 3-32 characters of a-z, 0-9, dot, dash or underscore');
  }
  return { username: args.username, role: args.role ?? 'owner', displayName: args.displayName, force: args.force };
}

/**
 * 24 bytes of base64url, which is ~144 bits.
 *
 * Long because nobody has to remember it — it goes into a password manager on
 * the way from this terminal to the login form, and the operator changes it or
 * does not. Short enough to select in one double-click, which matters more than
 * it sounds when the alternative is somebody retyping it wrong four times.
 */
function generatePassword(): string {
  return randomBytes(24).toString('base64url');
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  // Migrating first, so this works on a database that has never been migrated —
  // which is the state a brand new deployment is in, and the state somebody
  // running this command is most likely to be standing in.
  await migrate();

  if (!args.force && (await hasAnyAdmin())) {
    console.error(
      'error: this server already has at least one enabled operator.\n' +
        'Create further operators from the panel, where the action is recorded in the\n' +
        'audit log against whoever took it. Pass --force to create one anyway.',
    );
    process.exit(1);
  }

  const supplied = process.env.ADMIN_PASSWORD;
  if (supplied !== undefined && supplied.length < 12) {
    console.error('error: ADMIN_PASSWORD must be at least 12 characters');
    process.exit(2);
  }
  const password = supplied ?? generatePassword();

  let created;
  try {
    created = await createAdminUser({
      username: args.username,
      password,
      role: args.role,
      displayName: args.displayName,
    });
  } catch (err) {
    if ((err as { code?: string }).code === '23505') {
      console.error(`error: an operator named '${args.username}' already exists`);
      process.exit(1);
    }
    throw err;
  }

  console.log(`\nOperator created.\n`);
  console.log(`  username  ${created.username}`);
  console.log(`  role      ${created.role}`);
  if (!supplied) {
    console.log(`  password  ${password}`);
    console.log(`\nThis password is not stored anywhere and is not shown again.`);
  }
  console.log(
    `\nSign in at the admin panel and enrol two-factor immediately: until you do,\n` +
      `this password is the only thing between anyone and every account on this server.\n`,
  );
}

await main();
await pool.end();
