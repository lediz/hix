PROCEDURE Main(...)

   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown", "roles" => {=>} } )
   LOCAL cName := hUser['name']
   LOCAL cKey, cRoles := '' 
   
   // Handle numeric ROLES (backward compat with old session data)
   IF ValType( hUser["roles"] ) == "N"
      cRoles := ltrim(str(hUser["roles"]))
   ELSE
      FOR EACH cKey IN hUser["roles"]
         cRoles += cKey:__enumKey() + " "
      NEXT
   ENDIF
   
   IF Empty( cRoles ) ; cRoles := "(none)" ; ENDIF  
   
RETURN UView( 'main.html', cName, hUser, cRoles )

