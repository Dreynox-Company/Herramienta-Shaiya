#!/usr/bin/env python3
"""Adapt the offline backend to the inspected, hash-pinned ps0032 client.
The native client serializes the same variable-length launcher token with A114
at VA 00560728 and A110 at 005607B8. Never disable password verification.
"""
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve(); changes=[]
def patch(path,old,new):
 p=root/path;s=p.read_text(encoding='utf-8-sig')
 if s.count(old)!=1:raise RuntimeError('Protocol source contract changed: '+path)
 before=hashlib.sha256(p.read_bytes()).hexdigest();p.write_text(s.replace(old,new),encoding='utf-8')
 changes.append({'path':path,'beforeSha256':before,'afterSha256':hashlib.sha256(p.read_bytes()).hexdigest()})
patch('src/Imgeneus.Network/Packets/PacketType.cs','OAUTH_LOGIN_REQUEST = 0xA110,','OAUTH_LOGIN_REQUEST = 0xA110,\n#if DREYNOX_OFFLINE\n        LOCAL_LAUNCHER_LOGIN = 0xA114,\n#endif')
patch('src/Imgeneus.Login/Handlers/AuthenticationHandler.cs','        private async Task HandleAuthentication(LoginClient sender, string username, string password)','''#if DREYNOX_OFFLINE
        [HandlerAction(PacketType.LOCAL_LAUNCHER_LOGIN)]
        public async Task HandleLocalLauncher(LoginClient sender, OAuthAuthenticationPacket packet)
        {
            if (!System.Net.IPAddress.IsLoopback(((System.Net.IPEndPoint)sender.Socket.RemoteEndPoint).Address))
                throw new InvalidOperationException("Local launcher packets require loopback.");
            await HandleOauth(sender, packet);
        }
#endif

        private async Task HandleAuthentication(LoginClient sender, string username, string password)''')
patch('src/Imgeneus.Network/Packets/Login/OAuthAuthenticationPacket.cs','            key = packetStream.ReadString(40);','''#if DREYNOX_OFFLINE
            var remaining = packetStream.Length - packetStream.Position;
            if (remaining < 3 || remaining > 128) throw new System.FormatException("Invalid local launcher token length.");
            key = packetStream.ReadString((int)remaining, System.Text.Encoding.ASCII);
            var separator = key.IndexOf(':');
            if (separator < 1 || separator != key.LastIndexOf(':') || separator == key.Length - 1)
                throw new System.FormatException("Invalid local launcher token shape.");
            foreach (var character in key)
                if (character < 33 || character > 126) throw new System.FormatException("Invalid local launcher token character.");
#else
            key = packetStream.ReadString(40);
#endif''')
(root/'OFFLINE_PROTOCOL_MANIFEST.json').write_text(json.dumps({'schema':1,'nativeSha256':'509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d','tokenWriters':{'0x00560728':'A114 followed by std::string.length bytes','0x005607B8':'A110 followed by std::string.length bytes'},'passwordValidation':'unchanged Identity PasswordHasher','nativeExecutablePatched':False,'changes':changes},indent=2))
print('Local launcher A114 handler prepared; requires real native-session verification.')
