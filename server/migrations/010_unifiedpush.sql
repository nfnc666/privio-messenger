-- A wake-up path that is not Apple's or Google's.
--
-- Privio Libre ships without Firebase, so until now it had no way to be woken
-- at all: it received while it was running and not otherwise. UnifiedPush
-- fixes that without a proprietary SDK — the device registers an endpoint URL
-- belonging to a distributor it chose (often self-hosted), and this server
-- POSTs to it.
--
-- push_token holds that URL. It is a different kind of value from an APNs or
-- FCM token — an address this server will make an outbound request to, rather
-- than a handle a vendor resolves — which is why it is validated as a public
-- HTTPS URL on the way in and re-checked before every send.
ALTER TABLE devices DROP CONSTRAINT devices_push_provider_check;

ALTER TABLE devices ADD CONSTRAINT devices_push_provider_check
  CHECK (push_provider IN ('apns', 'fcm', 'unifiedpush'));

COMMENT ON COLUMN devices.push_token IS
  'APNs/FCM: the vendor token. UnifiedPush: the distributor endpoint URL. Never content.';
