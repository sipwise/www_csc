for html in *.html
do
  cat header $html footer >../root/$html
done
