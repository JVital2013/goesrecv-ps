#####
# PowerShell implementation of nanomsg inspired by sam210723 https://github.com/sam210723/goesrecv-monitor/blob/master/goesrecv-monitor/Symbols.cs
#####

$ip = "192.168.1.137"
$port = "5000"
$outfile = "C:\outfolder"
$maxSize = 2136997888

#Initialize nanomsg subscription to goesrecv
[byte[]] $nninit = 0x00, 0x53, 0x50, 0x00, 0x00, 0x21, 0x00, 0x00

#Expected goesrecv response to nanomsg subscription
[byte[]] $nnires = 0x00, 0x53, 0x50, 0x00, 0x00, 0x20, 0x00, 0x00

#Set up other variables
$socket = New-Object System.Net.Sockets.Socket -ArgumentList $([System.Net.Sockets.SocketType]::Stream), $([System.Net.Sockets.ProtocolType]::Tcp)
$res = [System.Byte[]]::CreateInstance([System.Byte], 8)
$dres = [System.Byte[]]::CreateInstance([System.Byte], 65536)
$num = 0
$totalBytes = 0

#Connect to goesrecv SDR sample publisher
try
{
    Write-Output "Connecting to goesresv host..."
    $socket.Connect($ip, $port)
    $socket.Send($nninit) | Out-Null
    $socket.Receive($res) | Out-Null

    if(-not [System.Linq.Enumerable]::SequenceEqual($nnires, $res))
    {
        Write-Warning "Could Not Connect to host"
        $socket.Close()
        exit
    }
}
catch
{
    Write-Warning "Could Not Connect to host"
    exit
}

Write-Output "Connected to goesresv host!"

#Listen for packets forever, splitting files at the specified size
$newFile = $true
do {

    if($newFile -eq $true)
    {
        $newName = "$outfile\$(Get-Date -UFormat %s -Millisecond 0).iq"
        $FileStream = New-Object System.IO.FileStream -ArgumentList $newName, $([System.IO.FileMode]::Create)
        Write-Output "Writing to $newName..."
        $newFile = $false
    }

    $num = $socket.Receive($dres)
    $FileStream.Write($dres, 0, $num)
    $totalBytes += $num

    if($maxSize -ne 0 -and $totalBytes -gt $maxSize)
    {
        $FileStream.Close()
        $totalBytes = 0
        $newFile = $true
    }

} while($num -ne 0)


#Clean Up after no packets were received from the server
Write-Warning "Connection to the server closed"
$FileStream.Close()
$socket.Close()
