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
  /** Removing comments and silencing people in a discussion under a post. */
  canModerateDiscussion: boolean;
  /** Rotating the invite link, setting its limits, admitting people waiting. */
  canManageInvites: boolean;
  canManageLivestreams: boolean;
  /**
   * Making somebody else an admin.
   *
   * Deliberately not implied by [canManageMembers]. An admin who may remove a
   * spammer should not thereby be able to appoint a second admin who can remove
   * them back.
   */
  canAppointAdmins: boolean;
}

export type ChannelPermission = keyof ChannelPermissions;

export const NO_PERMISSIONS: ChannelPermissions = {
  canPost: false,
  canEditChannel: false,
  canDeletePosts: false,
  canManageMembers: false,
  canDeleteChannel: false,
  canModerateDiscussion: false,
  canManageInvites: false,
  canManageLivestreams: false,
  canAppointAdmins: false,
};

/** The owner holds everything, and that is not stored or revocable. */
export const OWNER_PERMISSIONS: ChannelPermissions = {
  canPost: true,
  canEditChannel: true,
  canDeletePosts: true,
  canManageMembers: true,
  canDeleteChannel: true,
  canModerateDiscussion: true,
  canManageInvites: true,
  canManageLivestreams: true,
  canAppointAdmins: true,
};

/** What a new admin gets when the caller does not say otherwise. */
export const DEFAULT_ADMIN_PERMISSIONS: ChannelPermissions = {
  canPost: true,
  canEditChannel: true,
  canDeletePosts: true,
  canManageMembers: false,
  canDeleteChannel: false,
  canModerateDiscussion: true,
  canManageInvites: true,
  canManageLivestreams: true,
  // Never by default. Appointing admins is the one permission that multiplies
  // itself, so it is always a deliberate grant.
  canAppointAdmins: false,
};

export function permissionsFromRow(row: {
  role: string;
  can_post: boolean;
  can_edit_channel: boolean;
  can_delete_posts: boolean;
  can_manage_members: boolean;
  can_delete_channel: boolean;
  can_moderate_discussion?: boolean;
  can_manage_invites?: boolean;
  can_manage_livestreams?: boolean;
  can_appoint_admins?: boolean;
}): ChannelPermissions {
  if (row.role === 'owner') return OWNER_PERMISSIONS;
  return {
    canPost: row.can_post,
    canEditChannel: row.can_edit_channel,
    canDeletePosts: row.can_delete_posts,
    canManageMembers: row.can_manage_members,
    canDeleteChannel: row.can_delete_channel,
    // Optional on the row so a query that selects the older five still
    // type-checks; absent reads as not granted, which is the safe direction.
    canModerateDiscussion: row.can_moderate_discussion ?? false,
    canManageInvites: row.can_manage_invites ?? false,
    canManageLivestreams: row.can_manage_livestreams ?? false,
    canAppointAdmins: row.can_appoint_admins ?? false,
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
