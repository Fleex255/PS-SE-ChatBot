# Configuration
$useragent = 'A Stack Exchange chat bot by Ben N. It uses PowerShell!'
$email = 'me@example.com' # These two lines should be edited...
$password = 'GoodPassword' # ...to set the credentials of the account.
$roomurl = 'http://chat.stackexchange.com/rooms/40974/bot-overflow' # Change these two lines...
$roomid = '40974' # ...to set the room the bot appears in.
Function PostData($url, $data) {
	Return Invoke-WebRequest $url -Method Post -Body $data -WebSession $script:session -UserAgent $script:useragent
}
Function ExtractHexId($content, $fieldname) {
	$content -match ('name="' + $fieldname + '" value="([0-9a-f---]*)"') | Out-Null
	Return $matches[1]
}
# Bot state
$usercommands = Import-Clixml '.\botcommands.xml'
# Log in
$startpage = Invoke-WebRequest 'http://stackexchange.com/users/login?returnurl=http%3a%2f%2fchat.stackexchange.com%2f#log-in' -SessionVariable session -UserAgent $useragent
$loginfkey = ExtractHexId $startpage.Content 'fkey'
$openidpage = PostData 'https://stackexchange.com/users/authenticate' @{'fkey' = $loginfkey; 'openid_identifier' = 'https://openid.stackexchange.com/'}
$submitpage = PostData 'https://openid.stackexchange.com/account/login/submit' @{'fkey' = (ExtractHexId $openidpage.Content 'fkey'); 'session' = (ExtractHexId $openidpage.Content 'session'); 
                                                                                 'email' = $email; 'password' = $password}
# Chat functions
$lastmsg = 0
Function PostMessage($text) {
	PostData "http://chat.stackexchange.com/chats/$roomid/messages/new" @{'text' = $text; 'fkey' = $fkey} | Out-Null
}
Function PostReplyMessage($target, $text) {
	PostMessage (':' + $target.message_id + ' ' + $text)
}
Function GetRecentMessages($scrap) {
	$roomrecent = PostData "http://chat.stackexchange.com/chats/$roomid/events" @{'msgCount' = '10'; 'since' = '0'; 'mode' = 'Messages'; 'fkey' = $fkey}
	$roomdata = ConvertFrom-Json $roomrecent.Content
	$retdata = $null
	If (-not $scrap) {
		$retdata = $roomdata.events | ? {$_.message_id -gt $script:lastmsg}
	}
	$script:lastmsg = $roomdata.events[-1].message_id
	Return $retdata
}
Function AppearInRoom($newroomid) {
	PostData 'http://chat.stackexchange.com/events' @{"r$newroomid" = '0'; 'fkey' = $fkey} | Out-Null
}
# Participate in the room
$roompage = PostData $roomurl $null
$fkey = ExtractHexId $roompage.Content 'fkey" type="hidden' # This page has the fields in a different order
AppearInRoom $roomid
GetRecentMessages $true
Do {
	GetRecentMessages $false | % {
		If ($_.content.StartsWith('$ Get-BotStatus')) {
			PostMessage (":$($_.message_id) Running")
		} ElseIf ($_.content.StartsWith('$$&gt;')) { # Do some math
			$expr = $_.content.Substring(6)
			$good = $true
			ForEach ($c In $expr.ToCharArray()) {
				If (-not ' 0123456789.()+-*/'.Contains($c)) {
					$good = $false
					Break
				}
			}
			If ($good) {
				$result = iex $expr -ErrorAction SilentlyContinue
				If ($result -ne $null) {
					PostMessage (":$($_.message_id) $result")
				} Else {
					PostMessage (":$($_.message_id) Parse error")
				}
			} Else {
				Write-Host 'Bad math!'
			}
		} ElseIf ($_.content -match '^\$ Add-BotCommand -ShortName (\S*) -ResponseText (.*)$') {
			$cmdname = $matches[1].ToLowerInvariant()
			If ($usercommands.ContainsKey($cmdname)) {
				PostReplyMessage $_ "Command $cmdname already exists."
			} Else {
				$usercommands[$cmdname] = $matches[2]
				PostReplyMessage $_ "Command $cmdname learned."
			}
		} ElseIf ($_.content -match '\$\$(\S*)') {
			$cmdname = $matches[1].ToLowerInvariant()
			If ($usercommands.ContainsKey($cmdname)) {
				PostReplyMessage $_ $usercommands[$cmdname]
			} ElseIf (-not $_.content.StartsWith('$$$')) { # Don't bother people talking about money
				PostReplyMessage $_ "Unknown user command $cmdname."
			}
		} ElseIf ($_.content.StartsWith('$ Write-CurrentConfig')) {
			$usercommands | Export-Clixml '.\botcommands.xml'
		}
	}
	Start-Sleep -Seconds 6
} While ($true)