require 'korundum4'
require 'ktexteditor'

require 'lib/app'

app = Qt::Application.new ARGV
Kodr::App.new
app.exec