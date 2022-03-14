#####
# PowerShell implementation of nanomsg inspired by sam210723 https://github.com/sam210723/goesrecv-monitor/blob/master/goesrecv-monitor/Symbols.cs
#####

$ip = "192.168.1.137"
$port = "5000"
$outfile = "C:\outfolder"
$maxSize = 0

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
$bytesBeforeHeader = 0
do {

    try
    {
        #Make new file, if necessary
        if($newFile -eq $true)
        {
            $newName = "$outfile\$(Get-Date -UFormat %s -Millisecond 0).iq"
            $FileStream = New-Object System.IO.FileStream -ArgumentList $newName, $([System.IO.FileMode]::Create)
            Write-Output "Writing to $newName..."
            $newFile = $false
        }

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
                $FileStream.Write($dres, $startReadingAt, $bytesBeforeHeader)
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
        $FileStream.Write($dres, $startReadingAt, $remainingBytesToWrite)
        $bytesBeforeHeader -= $remainingBytesToWrite
        $totalBytes += $remainingBytesToWrite

        if($maxSize -ne 0 -and $totalBytes -gt $maxSize)
        {
            $FileStream.Close()
            $totalBytes = 0
            $newFile = $true
        }
    }
    catch
    {
        Write-Warning "Error saving iq files"
        $FileStream.Close()
        $socket.Close()
    }

} while($num -ne 0)


#Clean Up after no packets were received from the server
Write-Warning "Connection to the server closed"
$FileStream.Close()
$socket.Close()