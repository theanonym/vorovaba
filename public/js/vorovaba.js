function insertToPostform(str)
{
   var textarea = document.forms.replyform.text;
   textarea.value += str;
   textarea.focus();
}


function getCookie(name)
{
   with(document.cookie)
   {
      var regexp = new RegExp('(^|;\\s+)' + name + '=(.*?)(;|$)');
      var hit = regexp.exec(document.cookie);

      if(hit && hit.length > 2) return unescape(hit[2]);

      else return '';
   }
}

function setCookie(name, value, days)
{
   if(days)
   {
      var date=new Date();
      date.setTime(date.getTime() + days*24*60*60*1000);
      var expires = '; expires=' + date.toGMTString();

   }
   else expires = '';

   document.cookie = name + '=' + value + expires + '; path=/';
}

function changeStyle()
{
   var e = document.getElementById("switch-style");
   set_stylesheet(e.options[e.selectedIndex].value);
}










function expandImage(post, num, src, thumb_src, n_w, n_h, o_w, o_h)
{
   if(n_w>screen.width)
   {
      n_h=((screen.width-80)*n_h)/n_w;
      n_w=screen.width-80;
   }

   document.getElementById('image' + '-' + post + '-' + num).innerHTML =
      '<a href="' + src + '" onclick="expandImage(' + post + "," + num + ",'" + src + "','" + thumb_src + "'," +
      o_w + ',' + o_h + ',' + n_w + ',' + n_h + '); return false;"><img src="' +
      (n_w > o_w && n_h > o_h ? src : thumb_src) +
      '" width="' + n_w + '" height="' + n_h + '" class="thumb" /></a>';
}

function set_stylesheet(styletitle, norefresh, target)
{
   setCookie("style",styletitle,365);
        var links = target ? target.document.getElementsByTagName("link") : document.getElementsByTagName("link");
   var found=false;
   for(var i=0;i<links.length;i++)
   {
      var rel=links[i].getAttribute("rel");
      var title=links[i].getAttribute("title");
      if(rel.indexOf("style")!=-1&&title)
      {
         links[i].disabled=true; // IE needs this to work. IE needs to die.
         if(styletitle==title) { links[i].disabled=false; found=true; }
      }
   }
   if(!found) set_preferred_stylesheet();
}
function set_preferred_stylesheet(target)
{
        var links = target ? target.document.getElementsByTagName("link") : document.getElementsByTagName("link");
   for(var i=0;i<links.length;i++)
   {
      var rel=links[i].getAttribute("rel");
      var title=links[i].getAttribute("title");
      if(rel.indexOf("style")!=-1&&title) links[i].disabled=(rel.indexOf("alt")!=-1);
   }
}
function get_active_stylesheet()
{
   var links=document.getElementsByTagName("link");
   for(var i=0;i<links.length;i++)
   {
      var rel=links[i].getAttribute("rel");
      var title=links[i].getAttribute("title");
      if(rel.indexOf("style")!=-1&&title&&!links[i].disabled) return title;
   }
   return null;
}
function get_preferred_stylesheet()
{
   var links=document.getElementsByTagName("link");
   for(var i=0;i<links.length;i++)
   {
      var rel=links[i].getAttribute("rel");
      var title=links[i].getAttribute("title");
      if(rel.indexOf("style")!=-1&&rel.indexOf("alt")==-1&&title) return title;
   }
   return null;
}
