#!/usr/bin/env python3
"""Adapt the pinned backend to the inspected original ps0032 client.
SHA-256 509c4a8f...73c2d: 0x5606f0 emits 0xA114 + string bytes; 0x560780
emits the same layout under 0xA110. Both go through existing RSA/AES and the
password verifier. No successful login is fabricated and no secret is logged.
"""
from pathlib import Path
import json,sys
root=Path(sys.argv[1]).resolve()
def patch(name,old,new):
 p=root/name;s=p.read_text(encoding='utf-8-sig')
 if s.count(old)!=1:raise RuntimeError('Pinned protocol contract changed: '+name)
 p.write_text(s.replace(old,new),encoding='utf-8')
patch('src/Imgeneus.Login/Handlers/AuthenticationHandler.cs',
 '        private async Task HandleAuthentication(LoginClient sender, string username, string password)',
 '''        [HandlerAction((PacketType)0xA114)]
        public Task HandleLocalLauncher(LoginClient sender, OAuthAuthenticationPacket packet)
        {
            // Same bounded payload as A110 in the fingerprinted client.
            // This is a protocol alias, not a bypass of Authentication().
            return HandleOauth(sender, packet);
        }

        private async Task HandleAuthentication(LoginClient sender, string username, string password)''')
patch('src/Imgeneus.Network/Packets/Login/OAuthAuthenticationPacket.cs',
 '            key = packetStream.ReadString(40);',
 '''            var remaining = packetStream.Length - packetStream.Position;
            if (remaining < 3 || remaining > 160)
                throw new System.ArgumentException("Invalid local-launch credential length.");
            key = packetStream.ReadString(checked((int)remaining), System.Text.Encoding.ASCII);
            if (key.Length < 3 || key.Any(c => c < 33 || c > 126) || key.Count(c => c == ':') != 1)
                throw new System.ArgumentException("Invalid local-launch credential syntax.");''')
p=root/'src/Imgeneus.Network/Packets/Login/OAuthAuthenticationPacket.cs';p.write_text('using System.Linq;\n'+p.read_text(),encoding='utf-8')
# Observe authenticated identities, never credential strings or packet bytes.
patch('src/Imgeneus.Login/Handlers/AuthenticationHandler.cs',
 '            sender.SetClientUserID(dbUser.Id);',
 '            sender.SetClientUserID(dbUser.Id);\n            System.Console.WriteLine("OFFLINE_AUTHENTICATED user=" + dbUser.Id);')
(root/'OFFLINE_PROTOCOL_MANIFEST.json').write_text(json.dumps({'schema':1,'clientSha256':'509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d','localLaunchOpcode':'0xA114','legacyOpcode':'0xA110','maximumCredentialBytes':160,'nativeClientPatched':False,'authentication':'existing password hashing and RSA/AES session, no bypass'},indent=2))
print('Pinned ps0032 local-launch protocol adapter applied; full native acceptance still required.')
