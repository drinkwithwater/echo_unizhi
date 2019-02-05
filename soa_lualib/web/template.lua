return [[ <head>
   <meta charset="utf-8">
   <script src="https://cdn.bootcss.com/jquery/2.1.1/jquery.min.js"></script>
   <!--script src="http://drinkwithwater.github.io/lib/vim.min.js"></script-->
   <script src="https://gitee.com/czasdf1234/repository/raw/master/lib/vim.min.js"></script>
   <script src="https://gitee.com/czasdf1234/repository/raw/master/lib/base64.min.js"></script>
   <script src="https://gitee.com/czasdf1234/repository/raw/master/wom/wom.js"></script>
   <script src="https://gitee.com/czasdf1234/repository/raw/master/pako/pako.js"></script>
   <link rel=stylesheet type=text/css href="https://gitee.com/czasdf1234/repository/raw/master/wom/wom.css">
<style>
textarea {
	width : 500px;
	height : 300px;
}
</style>
</head>
<body>
%s
<script>
$(document).ready(function(){
	$("input").click(function(){
		$(this).next().toggle();
	});
	$("span>span>span>span").hide();
	$("#back").click(function(){
		self.location = window.location.pathname
	});
	vim.open({
		debug : true,
		showMsg: function(msg){
			alert('msg:' + msg);
		}
	});
})

</script>

<input id="back" type="button" value="back">

<form action="" id = "inject"> <input type ="submit" value="inject"> </form>


<textarea name="inject" form="inject"> </textarea>

</body>
]]
