#!/usr/bin/env python3
"""Hotfix for the native ps0032 launcher login path used by the local-only build.

The exact client sends 0xA114 before 0xA110 when started with the "start" command.
Old Imgeneus does not know 0xA114, and its generic OAuth parser expects the updater
key format. In the DREYNOX_OFFLINE build only, accept the preflight packet and bind
0xA110 to the single loopback local account whose password is already held in the
service environment. Normal/non-offline builds are untouched.
"""
from pathlib import Path
import hashlib, json, sys

root = Path(sys.argv[1]).resolve()

handler_path = root / "src/Imgeneus.Login/Handlers/AuthenticationHandler.cs"
text = handler_path.read_text(encoding="utf-8-sig")

anchor = '''        /// <summary>
        /// Handles the Oauth packet.
        /// </summary>
        [HandlerAction(PacketType.OAUTH_LOGIN_REQUEST)]
        public async Task HandleOauth(LoginClient sender, OAuthAuthenticationPacket packet)
        {
            // TODO(OAuth): Should we actually implement OAuth? Perhaps a custom updater distribution is desired.
            // For now, let's just parse the key as a username/password combination.
            var parts = packet.key.Split(":");
            var username = parts.FirstOrDefault();
            var password = parts.LastOrDefault();

            if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(password))
            {
                /*
                 * The client doesn't handle unsuccessful login responses after attempting to login with an OAuth key,
                 * as it expects the key to always be valid (having been authenticated in a prior step via the updater).
                 */
                _server.DisconnectUser(sender.Id);
                return;
            }

            await HandleAuthentication(sender, username, password);
        }
'''

replacement = '''        /// <summary>
        /// Native ps0032 launcher preflight. The client sends this immediately before A110.
        /// It does not require a response for the local "start" path.
        /// </summary>
        [HandlerAction((PacketType)0xA114)]
        public Task HandleNativeLauncherPreflight(LoginClient sender, OfflineLauncherInfoPacket packet)
        {
#if DREYNOX_OFFLINE
            Console.WriteLine("[DreynoxOffline] Native launcher preflight A114 received.");
#endif
            return Task.CompletedTask;
        }

        /// <summary>
        /// Handles the Oauth packet.
        /// </summary>
        [HandlerAction(PacketType.OAUTH_LOGIN_REQUEST)]
        public async Task HandleOauth(LoginClient sender, OAuthAuthenticationPacket packet)
        {
#if DREYNOX_OFFLINE
            // This service is loopback-only and contains exactly one private local account.
            // Do not depend on updater/OAuth token formatting from a particular client build.
            const string username = "localplayer";
            var password = Environment.GetEnvironmentVariable("SHAIYA_OFFLINE_PASSWORD");

            if (string.IsNullOrEmpty(password))
            {
                _server.DisconnectUser(sender.Id);
                return;
            }

            Console.WriteLine("[DreynoxOffline] Native OAuth A110 mapped to localplayer.");
            await HandleAuthentication(sender, username, password);
#else
            // TODO(OAuth): Should we actually implement OAuth? Perhaps a custom updater distribution is desired.
            // For now, let's just parse the key as a username/password combination.
            var parts = packet.key.Split(":");
            var username = parts.FirstOrDefault();
            var password = parts.LastOrDefault();

            if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(password))
            {
                /*
                 * The client doesn't handle unsuccessful login responses after attempting to login with an OAuth key,
                 * as it expects the key to always be valid (having been authenticated in a prior step via the updater).
                 */
                _server.DisconnectUser(sender.Id);
                return;
            }

            await HandleAuthentication(sender, username, password);
#endif
        }
'''

if anchor not in text:
    raise SystemExit("AuthenticationHandler contract changed; hotfix refused.")
text = text.replace(anchor, replacement, 1)
handler_path.write_text(text, encoding="utf-8")

packet_path = root / "src/Imgeneus.Login/Packets/OfflineLauncherInfoPacket.cs"
packet_path.parent.mkdir(parents=True, exist_ok=True)
packet_path.write_text(r'''using Imgeneus.Network.PacketProcessor;

namespace Imgeneus.Login.Packets
{
    /// <summary>
    /// ps0032 native launcher preflight (0xA114).
    /// The local client sends variable payload data that the offline login service
    /// intentionally does not trust or use. The following A110 performs the local bind.
    /// </summary>
    public record OfflineLauncherInfoPacket : IPacketDeserializer
    {
        public void Deserialize(ImgeneusPacket packetStream)
        {
            // Packet framing is already consumed by Imgeneus; no payload is required.
        }
    }
}
''', encoding="utf-8")

manifest = {
    "schema": 1,
    "scope": "DREYNOX_OFFLINE only",
    "nativeClientProfile": "ps0032",
    "preflightPacket": "0xA114",
    "oauthPacket": "0xA110",
    "offlineUser": "localplayer",
    "passwordSource": "SHAIYA_OFFLINE_PASSWORD environment variable",
    "nonOfflineOAuthPreserved": True,
    "handlerSha256": hashlib.sha256(handler_path.read_bytes()).hexdigest(),
    "packetSha256": hashlib.sha256(packet_path.read_bytes()).hexdigest(),
}
(root / "NATIVE_LOGIN_COMPAT_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

# Hard gate: ensure the intended branches are present in source before the build.
final = handler_path.read_text(encoding="utf-8")
for needle in ["(PacketType)0xA114", "DREYNOX_OFFLINE", "SHAIYA_OFFLINE_PASSWORD", "Native OAuth A110 mapped to localplayer"]:
    if needle not in final:
        raise SystemExit("Hotfix verification failed: " + needle)
print("Native login compatibility hotfix applied.")
