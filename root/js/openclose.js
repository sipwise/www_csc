aufzu = "open";
function openclose()
	{
		if (aufzu == "open")
			{
				document.getElementById('prodinfo1').style.display = 'inline';
				aufzu = "close";
			}
		else
			{
				document.getElementById('prodinfo1').style.display = 'none';
				aufzu = "open";
			}
	}