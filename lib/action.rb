module Kodr
  WORD_CHARS = 'a-zA-Z0-9_\?'
  
  class Action < KDE::Action
    cattr_accessor :all, :groups, :instance
    cattr_accessor :name, :description, :shortcut, :alternate_shortcut, :icon, :modes, :group, :checked, :enabled, :checkable,
                   :single_undo_step, :old_cursor_position
    
    self.all = []
    self.groups = {}
    
    def self.[](name)
      App.instance.action(name) || EditorSet.active.active_editor.view.action(name)
    end
    
    def self.mode(*values)
      modes(*values)
    end
    
    def self.inherited(klass)
      Kodr::Action.all << klass
      klass.single_undo_step = true
      klass.enabled = true
      klass.old_cursor_position = {}
    end
    
    def self.register
      if name && description
        log "registering action: #{name}"
        action = new(App.instance)
        action.register
        self.instance = action
      else
        log "ignoring action #{self}, name or description missing"
      end
    end
    
    # instance methods
    
    def register
      set_text(description)
      if s = shortcut
        if s.respond_to?(:call)
          s = s.call
        end
        kshortcut = KDE::Shortcut.new(s)
        if alternate_shortcut
          kshortcut.set_alternate(Qt::KeySequence.new(alternate_shortcut))
        end
        set_shortcut(kshortcut)
      end
      if icon
        set_icon(KDE::Icon.new(icon))
      end
      if group
        set_checkable(true)
        g = (groups[group] ||= Qt::ActionGroup.new(Kodr::App.instance))
        set_action_group(g)
        if checked
          set_checked(true)
        end
      end
      unless enabled
        set_enabled(false)
      end
      if checkable
        set_checkable(true)
      end
      _self = self
      App.instance.connect(self, SIGNAL("triggered()")) { _self.trigger }
      App.instance.action_collection.add_action(name, self)
    end
    
    def view
      EditorSet.active.active_editor.view
    end
    
    def document
      view.document
    end
    
    def run(env)
      call(env)
    end
    
    def call(env)
      raise RuntimeError.new("You must implement call(env) method!")
    end
    
    def trigger
      if modes.nil? || modes.include?(document.mode)
        begin
          if single_undo_step
            @_start_view = view
            document.start_editing
          end
          run(prepare_env)
        rescue => e
          puts "#{e.class}: #{e.message}"
          puts e.backtrace
        ensure
          if single_undo_step
            raise "Action #{name} changed active view while being in editing transaction!" if @_start_view != view
            document.end_editing
          end
        end
        old_cursor_position[view] = view.cursor_position
      else
        if shortcut.to_s.size == 1
          view.insert_text(shortcut)
        end
      end
    end
    
    def prepare_env
      env = {}
      
      # document end
      doc_end = document.document_end
      env.merge!(:document_end_line => doc_end.line, :document_end_column => doc_end.column)
      # cursor position
      cursor_position = view.cursor_position
      env.merge!(:line => cursor_position.line, :column => cursor_position.column)
      # cursor position changed?
      env.merge!(:cursor_position_changed => cursor_position != old_cursor_position[view])
      env.merge!(:char_before_cursor => document.character(KTextEditor::Cursor.new(cursor_position.line, cursor_position.column - 1)).to_s)
      # word before cursor
      if cursor_position.column > 0
        line_to_cursor = document.line(cursor_position.line)[0..cursor_position.column-1]
        match = /([#{WORD_CHARS}]+)$/.match(line_to_cursor)
        if match
          env.merge!(:word_before_cursor => match[1], :word_before_cursor_start => match.begin(1), :word_before_cursor_end => match.end(1))
        end
      end
      # word after cursor
      if cursor_position.column < document.line_length(cursor_position.line)
        line_from_cursor = document.line(cursor_position.line)[cursor_position.column..-1]
        match = /^([#{WORD_CHARS}]+)/.match(line_from_cursor)
        if match
          env.merge!(:word_after_cursor => match[1], :word_after_cursor_start => cursor_position.column + match.begin(1), :word_after_cursor_end => cursor_position.column + match.end(1))
        end
      end
      # word under cursor
      if env[:word_before_cursor] || env[:word_after_cursor]
        env[:word_under_cursor] = env[:word_before_cursor].to_s + env[:word_after_cursor].to_s
        env[:word_under_cursor_start] = env[:word_before_cursor_start] || env[:word_after_cursor_start]
        env[:word_under_cursor_end] = env[:word_after_cursor_end] || env[:word_before_cursor_end]
      end
      
      env
    end
  
    def selected_lines
      range = view.selection_range
      if range.is_valid
        start_line, end_line = range.start.line, range.end.line
        end_line -= 1 if range.end.column == 0
      else
        start_line = end_line = view.cursor_position.line
      end
      [start_line, end_line, range]
    end
    
  end

  class DocumentAction < Action
    def run(env)
      if view.selection
        env[:selected_text] = view.selection_text
      end
      response = call(env)
      if response
        view.remove_selection_text
        view.insert_text(response)
      end
    end
  end
  
end
