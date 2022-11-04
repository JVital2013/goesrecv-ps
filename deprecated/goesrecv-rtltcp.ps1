#####
# PowerShell implementation of nanomsg inspired by sam210723 https://github.com/sam210723/goesrecv-monitor/blob/master/goesrecv-monitor/Symbols.cs
# RTL_TCP Protocol Emulation based on https://hz.tools/rtl_tcp/ and https://github.com/osmocom/rtl-sdr/blob/master/src/rtl_tcp.c
#####

$goesrecvIP = "192.168.1.137"
$goesrecvPort = "5000"
$rtltcpPort = "1234"

#RTL_TCP header (emulates E4000 tuner; 1 gain control): RTL0 0001 0001
[byte[]] $magic = 0x52, 0x54, 0x4C, 0x30, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01

#Initialize nanomsg subscription to goesrecv
[byte[]] $nninit = 0x00, 0x53, 0x50, 0x00, 0x00, 0x21, 0x00, 0x00

#Expected goesrecv response to nanomsg subscription
[byte[]] $nnires = 0x00, 0x53, 0x50, 0x00, 0x00, 0x20, 0x00, 0x00

#Set up other variables
$socket = New-Object System.Net.Sockets.Socket -ArgumentList $([System.Net.Sockets.SocketType]::Stream), $([System.Net.Sockets.ProtocolType]::Tcp)
$endpoint = new-object System.Net.IPEndPoint -ArgumentList $([ipaddress]::Any), $rtltcpPort
$listener = new-object System.Net.Sockets.TcpListener -ArgumentList $endpoint
$res = [System.Byte[]]::CreateInstance([System.Byte], 8)
$dres = [System.Byte[]]::CreateInstance([System.Byte], 65536)
$num = 0

#Wait for RTL_TCP Client
try
{
    Write-Output "Waiting for RTL_TCP Client..."

    $listener.start() | Out-Null
    $client = $listener.AcceptTcpClient()
    $stream = $client.GetStream()
    $stream.Write($magic, 0, 12)

    Write-Output "Client Connected!"
}
catch
{
    Write-Warning "Could not connect to client"
    exit
}

#Connect to goesrecv SDR IQ sample publisher
try
{
    Write-Output "Connecting to goesresv host..."
    $socket.Connect($goesrecvIP, $goesrecvPort)
    $socket.Send($nninit) | Out-Null
    $socket.Receive($res) | Out-Null

    if(-not [System.Linq.Enumerable]::SequenceEqual($nnires, $res))
    {
        Write-Warning "Could Not Connect to goesrecv host"
        $socket.Close()
        $stream.Close()
        $listener.Stop()
        exit
    }
}
catch
{
    Write-Warning "Could Not Connect to goesrecv host"
    $socket.Close()
    $stream.Close()
    $listener.Stop()
    exit
}

Write-Output "Connected to goesresv host!"
Write-Output "Bridging goesrecv IQ samples to RTL_TCP client..."

#Listen for packets forever
$bytesBeforeHeader = 0
do {
    try
    {
        #Recieve all available bytes
        $num = $socket.Receive($dres)
        $remainingBytesToWrite = $num
        $startReadingAt = 0

        #Loop through all the nanomsg headers
        while($remainingBytesToWrite -gt $bytesBeforeHeader)
        {
            #Write any information before the header
            if($bytesBeforeHeader -gt 0)
            {
                $stream.Write($dres, $startReadingAt, $bytesBeforeHeader)
                $totalBytes += $bytesBeforeHeader
            }

            #Get next nanomsg packet length
            [System.Array]::Copy($dres, $bytesBeforeHeader + $startReadingAt, $res, 0, 8) | Out-Null
            if([Bitconverter]::IsLittleEndian) {[array]::Reverse($res)}
            $startReadingAt += $bytesBeforeHeader + 8
            $remainingBytesToWrite = $num - $startReadingAt
            $bytesBeforeHeader = [BitConverter]::ToUInt64($res, 0)
        }

        #No more headers in bytes we have; write the rest of the bytes
        $stream.Write($dres, $startReadingAt, $remainingBytesToWrite)
        $bytesBeforeHeader -= $remainingBytesToWrite
        $totalBytes += $remainingBytesToWrite
    }
    catch
    {
        Write-Output "Client and/or goesrecv have disconnected. Exiting"
        $socket.Close()
        $stream.Close()
        $listener.Stop()
        exit
    }

    #Sending small packets too often causes issues with some programs since rtl_tcp sends large blocks
    #of iq samples at a time (per Wireshark inspection). Slow things down a bit to prevent flooding
    #clients

    Start-Sleep -Milliseconds 1

} while($num -ne 0)


#Clean Up after no packets were received from the server
Write-Warning "Connection to goesrecv closed"
$socket.Close()
$stream.Close()
$listener.Stop()
