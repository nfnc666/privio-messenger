/**
 * What a channel member is allowed to do.
 *
 * Separate flags rather than one "admin" bit, because the interesting cases are
 * in between: someone who may publish but not hand out permissions, someone who
 * may moderate posts but not rename the channel.
 */
export interface ChannelPermissions {
  canPost: boolean;
  canEditChannel: boolean;
  canDeletePosts: boolean;
  canManageMembers: boolean;
  canDeleteChannel: boolean;
}

export type ChannelPermission = keyof ChannelPermissions;

export const NO_PERMISSIONS: ChannelPermissions = {
  canPost: false,
  canEditChannel: false,
  canDeletePosts: false,
  canManageMembers: false,
  canDeleteChannel: false,
};

/** The owner holds everything, and that is not stored or revocable. */
export const OWNER_PERMISSIONS: ChannelPermissions = {
  canPost: true,
  canEditChannel: true,
  canDeletePosts: true,
  canManageMembers: true,
  canDeleteChannel: true,
};

/** What a new admin gets when the caller does not say otherwise. */
export const DEFAULT_ADMIN_PERMISSIONS: ChannelPermissions = {
  canPost: true,
  canEditChannel: true,
  canDeletePosts: true,
  canManageMembers: false,
  canDeleteChannel: false,
};

export function permissionsFromRow(row: {
  role: string;
  can_post: boolean;
  can_edit_channel: boolean;
  can_delete_posts: boolean;
  can_manage_members: boolean;
  can_delete_channel: boolean;
}): ChannelPermissions {
  if (row.role === 'owner') return OWNER_PERMISSIONS;
  return {
    canPost: row.can_post,
    canEditChannel: row.can_edit_channel,
    canDeletePosts: row.can_delete_posts,
    canManageMembers: row.can_manage_members,
    canDeleteChannel: row.can_delete_channel,
  };
}

/**
 * True when [granted] contains nothing [holder] lacks.
 *
 * This is the rule that keeps "an admin may appoint admins" from meaning "an
 * admin may appoint someone who can remove them": you cannot hand out authority
 * you do not have.
 */
export function withinAuthority(
  holder: ChannelPermissions,
  granted: ChannelPermissions,
): boolean {
  return (Object.keys(granted) as ChannelPermission[]).every(
    (permission) => !granted[permission] || holder[permission],
  );
}
