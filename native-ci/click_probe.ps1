$ErrorActionPreference='Stop'
$env:SHAIYA_OFFLINE_SLOT=(Resolve-Path save).Path
$env:SHAIYA_OFFLINE_FACTION='light'
$env:SHAIYA_OFFLINE_PASSWORD=[Guid]::NewGuid().ToString('N').Substring(0,16)
$env:SHAIYA_OFFLINE_TOKEN=[Guid]::NewGuid().ToString('N')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeInput {
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr w,out RECT r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr w,ref POINT p);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
}
'@
function WaitPort([int]$Port){for($i=0;$i -lt 60;$i++){$s=[Net.Sockets.TcpClient]::new();try{$s.Connect('127.0.0.1',$Port);$s.Dispose();return}catch{$s.Dispose();Start-Sleep 1}};throw "Port $Port unavailable"}
function Shot([string]$Name){$r=[Windows.Forms.SystemInformation]::VirtualScreen;$b=[Drawing.Bitmap]::new($r.Width,$r.Height);$g=[Drawing.Graphics]::FromImage($b);$g.CopyFromScreen($r.Left,$r.Top,0,0,$r.Size);$b.Save((Join-Path (Resolve-Path proof) $Name));$g.Dispose();$b.Dispose()}
function Click([double]$X,[double]$Y){$game.Refresh();$h=$game.MainWindowHandle;[NativeInput]::SetForegroundWindow($h)|Out-Null;$r=[NativeInput+RECT]::new();[NativeInput]::GetClientRect($h,[ref]$r)|Out-Null;$p=[NativeInput+POINT]::new();$p.X=[int](($r.R-$r.L)*$X);$p.Y=[int](($r.B-$r.T)*$Y);[NativeInput]::ClientToScreen($h,[ref]$p)|Out-Null;[NativeInput]::SetCursorPos($p.X,$p.Y)|Out-Null;Start-Sleep -Milliseconds 400;[NativeInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 130;[NativeInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero);Start-Sleep 1}
$children=@()
try {
 $l=Start-Process (Resolve-Path services/login/Imgeneus.Login.exe) -WorkingDirectory (Resolve-Path services/login) -RedirectStandardOutput proof/login.txt -RedirectStandardError proof/login-error.txt -PassThru;$children+=$l;WaitPort 30800
 $w=Start-Process (Resolve-Path services/world/Imgeneus.World.exe) -WorkingDirectory (Resolve-Path services/world) -RedirectStandardOutput proof/world.txt -RedirectStandardError proof/world-error.txt -PassThru;$children+=$w;WaitPort 30810;Start-Sleep 4
 $path=(Get-Content game-path.txt -Raw).Trim()
 $game=Start-Process $path -WorkingDirectory (Split-Path $path) -ArgumentList @('start','127.0.0.1',"localplayer:$env:SHAIYA_OFFLINE_PASSWORD") -PassThru;$children+=$game
 Start-Sleep 12;Shot '01-server-list.png';Click 0.50 0.427;Click 0.449 0.851
 Start-Sleep 12;Shot '02-after-server.png'
 Start-Sleep 8;Shot '03-after-server.png'
 $game.Refresh();@{exited=$game.HasExited;title=$game.MainWindowTitle}|ConvertTo-Json|Set-Content proof/native-state.json
 Get-NetTCPConnection -ErrorAction SilentlyContinue|Where-Object {$_.LocalPort -in @(30800,30810) -or $_.RemotePort -in @(30800,30810)}|Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess|ConvertTo-Json|Set-Content proof/connections.json
 Get-ChildItem (Split-Path $path)|Select-Object Name,Length,Mode|ConvertTo-Json|Set-Content proof/public-client-root.json
} finally {
 foreach($c in $children){Stop-Process -Id $c.Id -Force -ErrorAction SilentlyContinue}
 foreach($f in Get-ChildItem proof -Filter *.txt){$s=Get-Content $f -Raw -ErrorAction SilentlyContinue;if($s){$s.Replace($env:SHAIYA_OFFLINE_PASSWORD,'[redacted]').Replace($env:SHAIYA_OFFLINE_TOKEN,'[redacted]')|Set-Content $f}}
}
