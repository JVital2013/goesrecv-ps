#####
# PowerShell implementation of nanomsg inspired by sam210723 https://github.com/sam210723/goesrecv-monitor/blob/master/goesrecv-monitor/Symbols.cs
#####

$ip = "192.168.1.137"
$port = "5004"
$logfile = "F:\vcid.csv"
$ignoreEmwinDcs = $true

#Initialize nanomsg subscription to goesrecv
[byte[]] $nninit = 0x00, 0x53, 0x50, 0x00, 0x00, 0x21, 0x00, 0x00

#Expected goesrecv response to nanomsg subscription
[byte[]] $nnires = 0x00, 0x53, 0x50, 0x00, 0x00, 0x20, 0x00, 0x00

#VCID Channel Lookup Table
$vcidLookup = @{}
$vcidLookup[0] = "Admin Text"
$vcidLookup[1] = "Mesoscale Imagery"
$vcidLookup[2] = "CMI Band 2 (Red)"
$vcidLookup[7] = "CMI Band 7 (Shortwave IR)"
$vcidLookup[8] = "CMI Band 8 (Upper Troposphere)"
$vcidLookup[9] = "CMI Band 9 (Mid Troposphere)"
$vcidLookup[13] = "CMI Band 13 (Clean Longwave IR)"
$vcidLookup[14] = "CMI Band 14 (Longwave IR)"
$vcidLookup[15] = "CMI Band 15 (Dirty Longwave IR)"
$vcidLookup[16] = "GOES-16 CMI Band 13 (Clean Longwave IR)"
$vcidLookup[17] = "GOES-17 CMI Band 13 (Clean Longwave IR)"
$vcidLookup[18] = "GOES-18 CMI Band 13 (Clean Longwave IR)"
$vcidLookup[20] = "EMWIN - Priority"
$vcidLookup[21] = "EMWIN - Graphics"
$vcidLookup[22] = "EMWIN - Other"
$vcidLookup[24] = "NHC Maritime Graphics Products"
$vcidLookup[25] = "GOES Level II Products"
$vcidLookup[30] = "DCS Admin"
$vcidLookup[32] = "DCS Data New Format"
$vcidLookup[60] = "Himawari-8"
$vcidLookup[63] = "Idle"

#Set up other variables
$socket = New-Object System.Net.Sockets.Socket -ArgumentList $([System.Net.Sockets.SocketType]::Stream), $([System.Net.Sockets.ProtocolType]::Tcp)
$res = [System.Byte[]]::CreateInstance([System.Byte], 8)
$dres = [System.Byte[]]::CreateInstance([System.Byte], 65536)
$buffer = [System.Byte[]]::CreateInstance([System.Byte], 65536)

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

#Create log file (if specified)
if(-not [String]::IsNullOrWhiteSpace($logfile)) {Set-Content -Path $logfile -Value "Start Time,VCID,Channel Name,Packet Count"}

#Listen for packets forever
$bytesBeforeHeader = 0
$packetCount = 0
$lastVCID = -1
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
				[System.Buffer]::BlockCopy($dres, $startReadingAt, $buffer, $totalBytes, $bytesBeforeHeader)
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
		[System.Buffer]::BlockCopy($dres, $startReadingAt, $buffer, $totalBytes, $remainingBytesToWrite)
		$bytesBeforeHeader -= $remainingBytesToWrite
		$totalBytes += $remainingBytesToWrite
	}
	catch
	{
		Write-Warning "Error parsing packet stream"
		$socket.Close()
		exit
	}

	#Parse for current channel
	$currentOffset = 0
	while($totalBytes -ge 892)
	{
		$vcid = $buffer[$currentOffset + 1] -band 0x3f
		if($vcid -ne $lastVCID)
		{
			#Skip emwin and DCS channels if specified, but count others here
			if($ignoreEmwinDcs -eq $false -or @(20, 21, 22, 32) -notcontains $vcid)
			{
				if($packetCount -ne 0)
				{
					Write-Output " - $packetCount packet$(if($packetCount -gt 1){"s"})"
					if(-not [String]::IsNullOrWhiteSpace($logfile)) {Add-Content -Path $logfile -Value "$packetCount"}
				}

				Write-Host "[$(Get-Date -Format G)] VCID $('{0:d2}' -f $vcid) - $($vcidLookup[$vcid])" -NoNewLine
				if(-not [String]::IsNullOrWhiteSpace($logfile)) {Add-Content -Path $logfile -Value "$(Get-Date -Format G),$vcid,$($vcidLookup[$vcid])," -NoNewline}

				$lastVCID = $vcid
				$packetCount = 0
			}

			#If ignoring emwin/dcs packets, don't count them to the channel currently transmitting
			else {$packetCount-- | Out-Null}
		}

		$packetCount++ | Out-Null
		$currentOffset += 892
		$totalBytes -= 892
	}

} while($num -ne 0)


#Clean Up after no packets were received from the server
Write-Warning "Connection to the server closed"
$socket.Close()