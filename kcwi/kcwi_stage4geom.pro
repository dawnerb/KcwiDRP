;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE4GEOM
;
; PURPOSE:
;	This procedure takes the data from basic CCD reduction through the
;	geometric correction, which includes solving for wavelength and 
;	spatial geometries.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE4GEOM, Pparfname, Linkfname
;
; OPTIONAL INPUTS:
;	Pparfname - input ppar filename generated by KCWI_STAGE2_PREP
;			defaults to './redux/kcwi.ppar'
;	Linkfname - input link filename generated by KCWI_PREP
;			defaults to './redux/kcwi.link'
;
; KEYWORDS:
;	SELECT	- set this keyword to select a specific image to process
;	PROC_IMGNUMS - set to the specific image numbers you want to process
;	PROC_CBARNUMS - set to the corresponding master dark image numbers
;	PROC_ARCNUMS - set to the corresponding master dark image numbers
;	NOTE: PROC_IMGNUMS and PROC_CBARNUMS and PROC_ARCNUMS must have the 
;		same number of items
;	VERBOSE	- set to verbosity level to override value in ppar file
;	DISPLAY - set to display level to override value in ppar file
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Outputs processed files in output directory specified by the
;	KCWI_PPAR struct read in from Pparfname.
;
; PROCEDURE:
;	Reads Pparfname to derive input/output directories and reads the
;	corresponding '*.link' file in output directory to derive the list
;	of input files and their associated geometric calibration files.
;
; EXAMPLE:
;	Perform stage4geom reductions on the images in 'night1/redux' directory:
;
;	KCWI_STAGE4GEOM,'night1/redux/kcwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-AUG-01	Initial version
;	2014-JAN-30	Handles failure to trace cbars
;	2014-APR-03	Use master ppar and link files
;	2014-MAY-13	Include calibration image numbers in headers
;	2014-SEP-29	Added infrastructure to handle selected processing
;       2015-APR-25     Added CWI flexure hooks (MM)
;	2016-OCT-05	Removed CWI flexure routines
;-
pro kcwi_stage4geom,ppfname,linkfname,help=help,select=select, $
	proc_imgnums=proc_imgnums, proc_cbarnums=proc_cbarnums, $
	proc_arcnums=proc_arcnums, $
	verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE4GEOM'
	startime=systime(1)
	q = ''	; for queries
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Ppar_filespec, Link_filespec'
		print,pre+': Info - default filespecs usually work (i.e., leave them off)'
		return
	endif
	;
	; get ppar struct
	ppar = kcwi_read_ppar(ppfname)
	;
	; verify ppar
	if kcwi_verify_ppar(ppar,/init) ne 0 then begin
		print,pre+': Error - pipeline parameter file not initialized: ',ppfname
		return
	endif
	;
	; directories
	if kcwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir) ne 0 then begin
		kcwi_print_info,ppar,pre,'Directory error, returning',/error
		return
	endif
	;
	; check keyword overrides
	if n_elements(verbose) eq 1 then $
		ppar.verbose = verbose
	if n_elements(display) eq 1 then $
		ppar.display = display
	;
	; specific images requested?
	if keyword_set(proc_imgnums) then begin
		nproc = n_elements(proc_imgnums)
		if n_elements(proc_cbarnums) ne nproc or $
		   n_elements(proc_arcnums) ne nproc then begin
			kcwi_print_info,ppar,pre,'Number of cbars and arcs must equal number of images',/error
			return
		endif
		imgnum = proc_imgnums
		cnums = proc_cbarnums
		anums = proc_arcnums
	;
	; if not use link file
	endif else begin
		;
		; read link file
		kcwi_read_links,ppar,linkfname,imgnum,cbar=cnums,arc=anums,count=nproc,select=select
		if imgnum[0] lt 0 then begin
			kcwi_print_info,ppar,pre,'reading link file',/error
			return
		endif
	endelse
	;
	; log file
	lgfil = reddir + 'kcwi_stage4geom.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+kcwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Filespec: '+ppar.filespec
	printf,ll,'Ppar file: '+ppar.ppfname
	if keyword_set(proc_imgnums) then begin
		printf,ll,'Processing images: ',imgnum
		printf,ll,'Using these cbars: ',cnums
		printf,ll,'Using these arcs : ',anums
	endif else $
		printf,ll,'Master link file: '+linkfname
	if ppar.saveintims eq 1 then $
		printf,ll,'Saving intermediate images'
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Plot display level: ',ppar.display
	if ppar.saveplots eq 1 then $
		printf,ll,'Saving plots'
	;
	; gather configuration data on each observation in reddir
	kcwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; check for flat fielded image first
		obfil = kcwi_get_imname(ppar,imgnum[i],'_intf',/reduced)
		;
		; if not check for dark subtracted image
		if not file_test(obfil) then $
			obfil = kcwi_get_imname(ppar,imgnum[i],'_intd',/reduced)
		;
		; if not just get stage1 output image
		if not file_test(obfil) then $
			obfil = kcwi_get_imname(ppar,imgnum[i],'_int',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(ppar,imgnum[i],'_icube',/reduced)
			;
			; get image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check if output file exists already
			if ppar.clobber eq 1 or not file_test(ofil) then begin
				;
				; print image summary
				kcwi_print_cfgs,kcfg,imsum,/silent
				if strlen(imsum) gt 0 then begin
					for k=0,1 do junk = gettok(imsum,' ')
					imsum = string(i+1,'/',nproc,format='(i3,a1,i3)')+' '+imsum
				endif
				print,""
				print,imsum
				printf,ll,""
				printf,ll,imsum
				flush,ll
				;
				; do we have the geom links?
				do_geom = (1 eq 0)
				if cnums[i] ge 0 and anums[i] ge 0 then begin
					;
					; get filenames
					cbf = kcwi_get_imname(ppar,cnums[i],/nodir)
					arf = kcwi_get_imname(ppar,anums[i],/nodir)
					;
					; get corresponding kgeom file
					gfile = cdir + strmid(cbf,0,strpos(cbf,'.fit'))+'_geom.save'
					;
					; if it exists restore it
					if file_test(gfile,/read) then begin
						restore,gfile
						do_geom = (kgeom.status eq 0)
						;
						; log it
						kcwi_print_info,ppar,pre,'Using geometry from',gfile,format='(a,a)'
					;
					; if not, derive it
					endif else begin
						;
						; time geometry generation
						gstartime = systime(1)
						;
						; get reduced images (assume dark subtracted images first)
						cbf = kcwi_get_imname(ppar,cnums[i],'_intd',/reduced)
						arf = kcwi_get_imname(ppar,anums[i],'_intd',/reduced)
						;
						; check for stage1 output images last
						if not file_test(cbf) or not file_test(arf) then begin
							cbf = kcwi_get_imname(ppar,cnums[i],'_int',/reduced)
							arf = kcwi_get_imname(ppar,anums[i],'_int',/reduced)
						endif
						;
						; log
						kcwi_print_info,ppar,pre,'Generating geometry solution'
						;
						; read configs
						ccfg = kcwi_read_cfg(cbf)
						acfg = kcwi_read_cfg(arf)
						;
						; get arc atlas
						kcwi_get_atlas,acfg,atlas,atname
						;
						; create a new Kgeom
						kgeom = {kcwi_geom}
						kgeom = struct_init(kgeom)
						kgeom.initialized = 1
						;
						; populate it with goodness
						kcwi_set_geom,kgeom,ccfg,ppar,atlas=atlas,atname=atname
						kgeom.cbarsfname = cbf
						kgeom.cbarsimgnum = ccfg.imgnum
						kgeom.arcfname = arf
						kgeom.arcimgnum = acfg.imgnum
						;
						; read in cbars image
						cbars = mrdfits(cbf,0,chdr,/fscale,/silent)
						;
						; trace the bars
						kcwi_trace_cbars,cbars,kgeom,ppar,status=stat
						;
						; check status, if < 0 don't proceed
						if stat ge 0 then begin
							;
							; log
							kcwi_print_info,ppar,pre,'traced continuum bars in cbars image',cbf,format='(a,a)'
							;
							; read in arcs
							arc = mrdfits(arf,0,ahdr,/fscale,/silent)
							;
							; extract along bars
							kcwi_extract_arcs,arc,kgeom,spec,ppar
							;
							; log
							kcwi_print_info,ppar,pre,'extracted arc spectra from arc image',arf,format='(a,a)'
							;
							; do the solution
							kcwi_solve_geom,spec,kgeom,ppar
							;
							; log bad solution
							if kgeom.status ne 0 then $
								kcwi_print_info,ppar,pre,'bad geometry solution',/error
						endif else $
							kcwi_print_info,ppar,pre,'unable to trace cont bars',/error
						;
						; write out result
						kcwi_write_geom,ppar,kgeom
						;
						; time for geometry
						eltime = systime(1) - gstartime
						print,''
						printf,ll,''
						kcwi_print_info,ppar,pre,'geom time in seconds',eltime
					endelse
					;
					; is our geometry good?
					if kgeom.status eq 0 then begin
						;
						; read in, update header, apply geometry, write out
						;
						; object image
						img = mrdfits(obfil,0,hdr,/fscale,/silent)
						;
						sxaddpar,hdr, 'HISTORY','  '+pre+' '+systime(0)
                                                ;
                                                kcwi_apply_geom,img,hdr,kgeom,ppar,cube,chdr                               
						;
						; write out intensity cube
						ofil = kcwi_get_imname(ppar,imgnum[i],'_icube',/nodir)
						kcwi_write_image,cube,chdr,ofil,ppar
						;
						; variance image
						vfil = repstr(obfil,'_int','_var')
						if file_test(vfil,/read) then begin
							var = mrdfits(vfil,0,varhdr,/fscale,/silent)
							;
							sxaddpar,varhdr,'HISTORY','  '+pre+' '+systime(0)
                                                        kcwi_apply_geom,var,varhdr,kgeom,ppar,vcub,vchdr
							;
							; write out variance cube
							ofil = kcwi_get_imname(ppar,imgnum[i],'_vcube',/nodir)
							kcwi_write_image,vcub,vchdr,ofil,ppar
						endif else $
							kcwi_print_info,ppar,pre,'no variance image found',/warning
						;
						; mask image
						mfil = repstr(obfil,'_int','_msk')
						if file_test(mfil,/read) then begin
							msk = float(mrdfits(mfil,0,mskhdr,/silent))
							;
                                                        sxaddpar,mskhdr,'HISTORY','  '+pre+' '+systime(0)
                                                        kcwi_apply_geom,msk,mskhdr,kgeom,ppar,mcub,mchdr   
							;
							; write out mask cube
							ofil = kcwi_get_imname(ppar,imgnum[i],'_mcube',/nodir)
							kcwi_write_image,mcub,mchdr,ofil,ppar
						endif else $
							kcwi_print_info,ppar,pre,'no mask image found',/warning
						;
						; check for nod-and-shuffle sky images
						sfil = kcwi_get_imname(ppar,imgnum[i],'_sky',/reduced)
						if file_test(sfil,/read) then begin
							sky = mrdfits(sfil,0,skyhdr,/fscale,/silent)
							;
							sxaddpar,skyhdr,'HISTORY','  '+pre+' '+systime(0)
                                                        kcwi_apply_geom,sky,skyhdr,kgeom,ppar,scub,schdr
							;
							; write out sky cube
							ofil = kcwi_get_imname(ppar,imgnum[i],'_scube',/nodir)
							kcwi_write_image,scub,schdr,ofil,ppar
						endif
						;
						; check for nod-and-shuffle obj images
						nfil = kcwi_get_imname(ppar,imgnum[i],'_obj',/reduced)
						if file_test(nfil,/read) then begin
							obj = mrdfits(nfil,0,objhdr,/fscale,/silent)
							;
                                                        sxaddpar,objhdr,'HISTORY','  '+pre+' '+systime(0)
                                                        kcwi_apply_geom,obj,objhdr,kgeom,ppar,ocub,ochdr
							;
							; write out obj cube
							ofil = kcwi_get_imname(ppar,imgnum[i],'_ocube',/nodir)
							kcwi_write_image,ocub,ochdr,ofil,ppar
						endif
					; end if geometry is good
					endif else $
						kcwi_print_info,ppar,pre,'unusable geom for: '+obfil+' type: '+kcfg.imgtype,/error
				;
				; end check cnums and anums links
				endif else $
					kcwi_print_info,ppar,pre,'missing calibration file(s) for: '+obfil,/warning
			;
			; end check if output file exists already
			endif else begin
				kcwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+kcfg.imgtype,/warning
				if ppar.clobber eq 0 and file_test(ofil) then $
					kcwi_print_info,ppar,pre,'processed file exists already',/warning
			endelse
		;
		; end check if input file exists
		endif else $
			kcwi_print_info,ppar,pre,'input file not found: '+obfil,/error
	endfor	; loop over images
	;
	; report
	eltime = systime(1) - startime
	print,''
	printf,ll,''
	kcwi_print_info,ppar,pre,'run time in seconds',eltime
	kcwi_print_info,ppar,pre,'finished on '+systime(0)
	;
	; close log file
	free_lun,ll
	;
	return
end
