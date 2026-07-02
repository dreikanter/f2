# Rails edge moved template handler registration to
# ActionView::Template::Handlers and removed the old
# ActionView::Template.template_handler_extensions, which ViewComponent's
# compiler still calls. Restore it until ViewComponent catches up.
ActiveSupport.on_load(:action_view) do
  unless ActionView::Template.respond_to?(:template_handler_extensions)
    ActionView::Template.singleton_class.define_method(:template_handler_extensions) do
      ActionView::Template::Handlers.extensions
    end
  end
end
