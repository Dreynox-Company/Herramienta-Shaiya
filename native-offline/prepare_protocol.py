#!/usr/bin/env python3
"""ps0032 interoperability adapter. A114 is binary-file metadata, NOT login.
At 0x542C48 the caller passes literal `game.exe` to 0x5427E0 and sends its
result via 0x5606F0 (A114), then separately sends the session string via
0x560780 (A110). Authentication/password checks remain unchanged.
"""
from pathlib import Path
import hashlib, json, sys
root=Path(sys.argv[1]).resolve(); changes=[]
def patch(path,old,new):
 p=root/path;s=p.read_text(encoding='utf-8-sig')
 if s.count(old)!=1:raise RuntimeError('Protocol source contract changed: '+path)
 before=hashlib.sha256(p.read_bytes()).hexdigest();p.write_text(s.replace(old,new),encoding='utf-8')
 changes.append({'path':path,'beforeSha256':before,'afterSha256':hashlib.sha256(p.read_bytes()).hexdigest()})
patch('src/Imgeneus.Network/Packets/PacketType.cs','OAUTH_LOGIN_REQUEST = 0xA110,','OAUTH_LOGIN_REQUEST = 0xA110,\n#if DREYNOX_OFFLINE\n        LOCAL_CLIENT_METADATA = 0xA114,\n#endif')
metadata='''using Imgeneus.Network.PacketProcessor;
namespace Imgeneus.Network.Packets.Login {
 public record LocalClientMetadataPacket : IPacketDeserializer {
  public int ByteCount {get;private set;}
  public void Deserialize(ImgeneusPacket packetStream) {
   var n=packetStream.Length-packetStream.Position;
   if(n<1||n>256) throw new System.FormatException("Client metadata length outside profile.");
   ByteCount=checked((int)n); packetStream.ReadString(ByteCount, System.Text.Encoding.ASCII);
  }
 }
}
'''
(root/'src/Imgeneus.Network/Packets/Login/LocalClientMetadataPacket.cs').write_text(metadata,encoding='utf-8')
patch('src/Imgeneus.Login/Handlers/AuthenticationHandler.cs','        private async Task HandleAuthentication(LoginClient sender, string username, string password)','''#if DREYNOX_OFFLINE
        [HandlerAction(PacketType.LOCAL_CLIENT_METADATA)]
        public Task HandleLocalMetadata(LoginClient sender, LocalClientMetadataPacket packet)
        {
            if (!System.Net.IPAddress.IsLoopback(((System.Net.IPEndPoint)sender.Socket.RemoteEndPoint).Address))
                throw new InvalidOperationException("Local profile requires loopback.");
            // Metadata never changes identity, roles or the authentication state.
            System.Console.WriteLine("OFFLINE_CLIENT_METADATA bytes="+packet.ByteCount);
            return Task.CompletedTask;
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
patch('src/Imgeneus.Login/Handlers/AuthenticationHandler.cs','            sender.SetClientUserID(dbUser.Id);','            sender.SetClientUserID(dbUser.Id);\n            System.Console.WriteLine("OFFLINE_AUTHENTICATED user="+dbUser.Id);')
(root/'OFFLINE_PROTOCOL_MANIFEST.json').write_text(json.dumps({'schema':2,'nativeSha256':'509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d','metadata':'A114 computed from game.exe; no identity change','authentication':'A110 bounded session string, unchanged Identity password check','evidence':['0x542C48 game.exe literal','0x542C5A file transform','0x542C69 metadata send','0x542C74 credentials send'],'nativeExecutablePatched':False,'changes':changes},indent=2))
print('Metadata and authentication separated. Native-session acceptance is a separate gate.')
