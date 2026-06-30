# DropdownMenuComponent styled for a page header: a square, bordered icon button
# matching the height and chrome of the Enable/Refresh buttons it sits beside.
# The dropdown template and behavior are inherited; only the trigger changes.
class HeaderMenuComponent < DropdownMenuComponent
  private

  def trigger_class
    "inline-flex items-center justify-center rounded-md border border-border bg-surface p-3 " \
      "text-slate-600 shadow-sm transition hover:bg-surface-muted focus:outline-none focus:ring-2 focus:ring-sky-500 " \
      "focus:ring-offset-1 cursor-pointer"
  end
end
