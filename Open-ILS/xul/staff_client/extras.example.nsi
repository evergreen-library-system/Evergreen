; Examples for extras file

!ifdef EXTERNAL_EXTRAS_SECMAIN ; Main install block
  ; Anything here will be done during install. Intended for shortcuts.

  ; Useful examples include having an exe in the branding directory
  CreateShortCut "$SMPROGRAMS\$ICONS_GROUP\My Program.lnk" "$INSTDIR\file.exe" "-somearg" "$INSTDIR\file.exe"

  ; Or perhaps wanting a special link to start evergreen? You can even auto-detect icon usage:
  !ifdef WICON
    CreateShortCut "$SMPROGRAMS\$ICONS_GROUP\Evergreen Staff Client Something.lnk" "$INSTDIR\evergreen.exe" "-something" "$INSTDIR\evergreen.ico"
  !else
    CreateShortCut "$SMPROGRAMS\$ICONS_GROUP\Evergreen Staff Client Something.lnk" "$INSTDIR\evergreen.exe" "-something"
  !endif
!else ifdef EXTERNAL_EXTRAS_UNINSTALL ; Uninstall block
  ; Anything you have added that you want removed may need uninstall lines

  ; Such as that extra exe? Left a file and a link.
  Delete "$INSTDIR\file.exe" 
  Delete "$SMPROGRAMS\$ICONS_GROUP\My Program.lnk"

  ; Or perhaps your extra start shortcuts?
  Delete "$SMPROGRAMS\$ICONS_GROUP\Evergreen Staff Client Something.lnk"
!endif
