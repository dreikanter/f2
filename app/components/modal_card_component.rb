# The sole card on a modal-layout page (sign-in, registration, password
# flows). Framed like a regular card from the sm breakpoint up; below it the
# card dissolves into the page, leaving the layout's own padding as the only
# inset.
class ModalCardComponent < CardComponent
  BASE_CLASSES = "w-full sm:rounded-lg sm:border sm:border-border sm:bg-surface sm:shadow-xs"
  PADDED_CLASSES = "sm:p-6"
end
