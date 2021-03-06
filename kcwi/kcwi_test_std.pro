;
; Copyright (c) 2014, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_TEST_STD
;
; PURPOSE:
;	Tests a standard star reduced with it's own inverse sensitivity.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_TEST_STD, Imno
;
; INPUTS:
;	Imno	- Image number of calibrated standard star observation
;
; OPTIONAL INPUTS:
;	Ppar	- KCWI_PPAR pipeline parameter struct
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	None
;
; KEYWORDS:
;	INSTRUMENT - set to show instrumental instead of overall efficiency
;	PS	- set to output postscript file
;	VERBOSE	- set for more output
;	DISPLAY	- set for more plots
;
; PROCEDURE:
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2014-APR-22	Initial Revision
;-
pro kcwi_test_std,imno,ppar,instrument=instrument,ps=ps, $
	verbose=verbose,display=display
	;
	; setup
	pre = 'KCWI_TEST_STD'
	version = kcwi_drp_version()
	q=''
	;
	; check input
	if n_params(0) lt 1 then begin
		print,pre+': Info - Usage: '+pre+', Imno <, Ppar>'
		return
	endif
	;
	; get params
	if n_elements(ppar) le 0 then begin
		pfile = 'kcwi.ppar'
		if not file_test(pfile) then begin
			pfile = 'redux/kcwi.ppar'
			if not file_test(pfile) then begin
				print,'Parameter file not found: ',pfile
				return
			endif
		endif
		ppar = kcwi_read_ppar(pfile)
	endif
	;
	; verify ppar
	if kcwi_verify_ppar(ppar,/init) ne 0 then begin
		print,pre + $
		    ': ERROR - pipeline parameter file not initialized: ' + $
		    ppfname
		return
	endif
	;
	; get input file
	ifil = kcwi_get_imname(ppar,imno,'_icubes',/reduced)
	if file_test(ifil) then begin
		kcfg = kcwi_read_cfg(ifil)
	endif else begin
		print,'Input file not found: ',ifil
		return
	endelse
	cfg = kcwi_cfg_string(kcfg,/delim,/long)
	kcfg.bgratnam = strtrim(kcfg.bgratnam,2)
	kcfg.ifunam = strtrim(kcfg.ifunam,2)
	;
	; get image number string
	imstr = string(imno,format='(i0'+strn(ppar.fdigits)+')')
	;
	; check keyword overrides
	if keyword_set(verbose) then $
		ppar.verbose = verbose
	if keyword_set(display) then $
		ppar.display = display
	;
	; log
	kcwi_print_info,ppar,pre,version
	;
	; is this a standard star object observation?
	if strmatch(strtrim(kcfg.imgtype,2),'object') eq 0 then begin
		kcwi_print_info,ppar,pre,'not a std obs',/warning
	endif
	;
	; directories
	if kcwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir,/read) ne 0 then begin
		kcwi_print_info,ppar,pre,'Directory error, returning',/error
		return
	endif
	;
	; check for effective area curve
	eafil = ppar.reddir + ppar.froot + $
		string(kcfg.imgnum,format='(i0'+strn(ppar.fdigits)+')') + $
		'_ea.fits'
	if not file_test(eafil) then begin
		kcwi_print_info,ppar,pre,'EA file not found',/error
		return
	endif
	rdfits1dspec,eafil,wea,ea,eahdr
	;
	; read in image (already extinction corrected)
	icub = kcwi_read_image(kcfg.imgnum,ppar,'_icubes',hdr,/calib, $
								status=stat)
	if stat ne 0 then begin
		kcwi_print_info,ppar,pre,'could not read input file',/error
		return
	endif
	;
	; check BUNIT
	bunit = strtrim(sxpar(hdr,'BUNIT'),2)
	if bunit eq 'FLAM16' then icub = icub / 1.d16
	;
	; check standard
	sname = kcwi_std_name(kcfg.targname)
	;
	; is standard file available?
	spath = !KCWI_DATA + '/stds/'+sname+'.fits'
	if not file_test(spath) then begin
		kcwi_print_info,ppar,pre, $
			'standard star data file not found for: '+sname,/error
		return
	endif
	kcwi_print_info,ppar,pre,'testing inverse sensitivity curve for '+sname
	;
	; get size
	sz = size(icub,/dim)
	;
	; default pixel ranges
	y = findgen(sz[2])
	y0 = 175
	y1 = sz[2] - 175
	;
	; get wavelength scale
	w0 = sxpar(hdr,'CRVAL3')
	dw = sxpar(hdr,'CD3_3')
	;
	; get all good wavelength range
	wgoo0 = sxpar(hdr,'WAVGOOD0') > 3650.00
	wgoo1 = sxpar(hdr,'WAVGOOD1')
	;
	; get all inclusive wavelength range
	wall0 = sxpar(hdr,'WAVALL0')
	wall1 = sxpar(hdr,'WAVALL1')
	;
	; get DAR padding in y
	pad_y = sxpar(hdr,'DARPADY')
	;
	; get sky subtraction status
	skycor = sxpar(hdr,'SKYCOR')
	;
	; compute good y pixel ranges
	if w0 gt 0. and dw gt 0. and wgoo0 gt 0. and wgoo1 gt 0. then begin
		y0 = fix( (wgoo0 - w0) / dw ) + 10
		y1 = fix( (wgoo1 - w0) / dw ) - 10
	endif
	gy = where(y ge y0 and y le y1)
	;
	; wavelength scale
	w = w0 + y*dw
	;
	; good spatial range
	gx0 = pad_y > 1
	gx1 = sz[1] - (pad_y > 2)
	;
	; log results
	kcwi_print_info,ppar,pre,'Invsens. Pars: X0, X1, Y0, Y1, Wav0, Wav1', $
		gx0,gx1,y0,y1,w[y0],w[y1],format='(a,4i6,2f9.3)'
	;
	; display status
	doplots = (ppar.display ge 2)
	;
	; get standard image params
	mxsl = sxpar(eahdr,'INVSLMX')
	sl0 = sxpar(eahdr,'INVSL0')
	sl1 = sxpar(eahdr,'INVSL1')
	cx = sxpar(eahdr,'INVSLY')
	xx = findgen(gx1-gx0)+gx0
	;
	; log results
	kcwi_print_info,ppar,pre,'Std slices; max, sl0, sl1, spatial cntrd', $
		mxsl,sl0,sl1,cx,format='(a,3i4,f9.2)'
	;
	; copy of input cube
	scub = icub
	;
	; sky window width in pixels
	skywin = ppar.psfwid/kcfg.xbinsize
	;
	; plotting prep
	deepcolor
	!p.background=colordex('white')
	!p.color=colordex('black')
	;
	; do sky subtraction, if needed
	if not skycor then begin
		for i=sl0,sl1 do begin
			skyspec = fltarr(sz[2])
			for j = 0,sz[2]-1 do begin
				skyv = reform(icub[i,gx0:gx1,j])
				good = where(xx le (cx-skywin) or $
					     xx ge (cx+skywin))
				sky = median(skyv[good])
				skyspec[j] = sky
				scub[i,*,j] = icub[i,*,j] - sky
			endfor
			if doplots then begin
				yrng = get_plotlims(skyspec[gy])
				plot,w,skyspec,title='Slice '+strn(i), $
				    xtitle='Wave (A)',xran=[wall0,wall1], /xs, $
				    ytitle='DN',yran=yrng,/ys
				oplot,[wgoo0,wgoo0],!y.crange, $
				    color=colordex('green'),thick=3
				oplot,[wgoo1,wgoo1],!y.crange, $
				    color=colordex('green'),thick=3
				read,'Next? (Q-quit plotting, <cr> - next): ',q
				if strupcase(strmid(strtrim(q,2),0,1)) eq 'Q' then $
					doplots = 0
			endif
		endfor
	endif	; do sky subtraction (not skycor)
	;
	; get slice spectra
	sx0 = (cx-skywin) > 0
	sx1 = (cx+skywin) < (sz[1]-1)
	slspec = total(scub[*,cx-skywin:cx+skywin,*],2,/nan)
	;
	; standard spectra
	stdspec = total(slspec[sl0:sl1,*],1,/nan)
	;
	; read in standard
	sdat = mrdfits(spath,1,shdr)
	swl = sdat.wavelength
	sflx = sdat.flux
	sfw = sdat.fwhm
	;
	; get region of interest
	sroi = where(swl ge w[0] and swl le w[n_elements(w)-1L], nsroi)
	if nsroi le 0 then begin
		kcwi_print_info,ppar,pre,'no standard wavelengths in common', $
									/error
		return
	endif
	;
	; expand range aftert checking for edges
	if sroi[0] gt 0 then begin
		sroi = [ sroi[0]-1, sroi ]
		nsroi += 1
	endif
	if sroi[nsroi-1] le n_elements(swl)-1L then begin
		sroi = [ sroi, sroi[nsroi-1]+1 ]
		nsroi += 1
	endif
	;
	; very sparsely sampled w.r.t. object
	if nsroi le 1 then begin
		kcwi_print_info,ppar,pre, $
			'not enough standard points',/error
		return
	endif
	kcwi_print_info,ppar,pre,'Number of standard points',nsroi
	;
	; how many points?
	if nsroi gt 20 then begin
		stdpsym = -3
		stdsymsi = 1
	endif else begin
		stdpsym = 4
		stdsymsi = 3.0
	endelse
	swl = swl[sroi]
	sflx = sflx[sroi]
	sfw = sfw[sroi]
	fwhm = max(sfw)
	kcwi_print_info,ppar,pre,'reference spectrum FWHM used',fwhm, $
		format='(a,f5.1)'
	;
	; resample onto our wavelength grid
	rsflx = interpol(sflx,swl,w,/nan,/spline)
	;
	; make a hardcopy if requested
	if keyword_set(ps) then begin
		font_store=!p.font
		cwv = strn(fix(kcfg.bcwave))
		psname = sname+'_' + kcfg.bgratnam + '_' + cwv + '_' + $
				     kcfg.ifunam + '_' + imstr
		psfile, psname
		deepcolor
		!p.background=colordex('white')
		!p.color=colordex('black')
		!p.font=0
	endif
	;
	; over plot standard
	yrng = get_plotlims(stdspec[gy])
	plot,w,stdspec,title=sname+' Img #: '+imstr+' '+cfg, $
		xran=[wall0,wall1], /xs,xtickformat='(a1)', $
		ytitle='!3Flam (erg s!U-1!N cm!U-2!N A!U-1!N)',yran=yrng,/ys, $
		pos=[0.15,0.30,0.95,0.95]
	oplot,sdat.wavelength,sdat.flux,color=colordex('red'),psym=stdpsym, $
		symsize=stdsymsi,thick=3
	oplot,w,rsflx,color=colordex('blue')
	oplot,[wgoo0,wgoo0],!y.crange,color=colordex('green'),thick=3
	oplot,[wgoo1,wgoo1],!y.crange,color=colordex('green'),thick=3
	kcwi_legend,['Cal. Flux','Obs. Flux','Interp'],linesty=[0,0,0], $
		color=[colordex('red'),colordex('black'),colordex('blue')], $
		/clear,clr_color=!p.background,/bottom,/right
	;
	; get residuals
	rsd = stdspec - rsflx
	frsd = 100.d0*(rsd/rsflx)
	mo = moment(rsd[gy],/nan)
	fmo = moment(frsd[gy],/nan)
	;
	; annotate residuals on main plot
	kcwi_legend,['<Resid> = '+strtrim(string(mo[0],format='(g13.3)'),2) + $
		' +- '+strtrim(string(sqrt(mo[1]),format='(g13.3)'),2)+' Flam',$
		'<Resid> = '+strtrim(string(fmo[0],format='(f8.2)'),2) + $
		' +- '+strtrim(string(sqrt(fmo[1]),format='(f8.2)'),2)+' %'], $
		/clear,clr_color=!p.background,/bottom;,/right
	;
	; plot residuals
	yrng = get_plotlims(rsd[gy])
	plot,w,rsd,xtitle='Wave (A)',xran=[wall0,wall1], /xs, $
		ytitle='!3Obs-Cal',yran=yrng,/ys,pos=[0.15,0.05,0.95,0.30], $
		/noerase
	oplot,!x.crange,[0,0]
	oplot,[wgoo0,wgoo0],!y.crange,color=colordex('green'),thick=3
	oplot,[wgoo1,wgoo1],!y.crange,color=colordex('green'),thick=3
	;
	; now plot efficiency and effective area
	;
	; get reference area
	tel = strtrim(sxpar(hdr,'telescop', count=ntel),2)
	if ntel le 0 then tel = 'Keck II'
	;
	; average extinction correction (atmosphere)
	atm = 1./( sxpar(hdr,'avexcor')>1. )
	;
	; defaults
	area = -1.0
	refl = 1.0
	;
	; ea file starts the title
	fdecomp,eafil,disk,dir,eaf,ext
	if strpos(tel,'Keck') ge 0 then begin
		area = 760000.d0	; Keck effective area in cm^2
		if keyword_set(instrument) then $
			refl = 0.658	; reflectivity (3-bounce @ 87% per)
	endif else if strpos(tel,'5m') ge 0 then begin
		area = 194165.d0	; Hale 5m area in cm^2
		if keyword_set(instrument) then $
			refl = 0.757	; reflectivity (2-bounce)
	endif
	if keyword_set(instrument) then begin
		area = area * refl * atm
		tlab = eaf+'  '+cfg+' '+tel+' * '+ $
			string(refl*100.,form='(i3)')+'% refl. * '+ $
			string(atm*100.,form='(i2)')+'% atmos.'
	endif else $
		tlab = eaf+' '+cfg+' '+tel+' at AIRMASS = '+ $
		strtrim(string(kcfg.airmass,form='(f7.3)'),2)
	if not keyword_set(ps) then $
		read,'next: ',q
	goo = where(wea gt wgoo0 and wea lt wgoo1, ngoo)
	if ngoo gt 5 then begin
		maxea = max(ea[goo,1])
		mo = moment(ea[goo,1])
		yrng = get_plotlims(ea[goo,1])
	endif else begin
		maxea = max(ea[*,1])
		mo = moment(ea[*,1])
		yrng = get_plotlims(ea[*,1])
	endelse
	if yrng[0] lt 0. then yrng[0] = 0.
	if area gt 0 then begin
		plot,wea,ea[*,0],xtitle='Wave (A)',xran=[wall0,wall1],/xs, $
			ytitle='!3EA (cm!U2!N)',title=tlab,ys=9, $
			yran=yrng,xmargin=[11,8]
		oplot,[wgoo0,wgoo0],!y.crange,color=colordex('green'), $
			thick=3
		oplot,[wgoo1,wgoo1],!y.crange,color=colordex('green'), $
			thick=3
		oplot,!x.crange,[maxea,maxea],linesty=2
		oplot,!x.crange,[mo[0],mo[0]],linesty=3
		axis,yaxis=1,yrange=100.*(!y.crange/area),ys=1, $
			ytitle='Efficiency (%)'
	endif else begin
		plot,wea,ea[*,0],xtitle='Wave (A)',xran=[wall0,wall1],/xs, $
			ytitle='!3EA (cm!U2!N)', yran=yrng, /ys, $
			title=tlab
		oplot,[wgoo0,wgoo0],!y.crange,color=colordex('green'), $
			thick=3
		oplot,[wgoo1,wgoo1],!y.crange,color=colordex('green'), $
			thick=3
		oplot,!x.crange,[maxea,maxea],linesty=2
		oplot,!x.crange,[mo[0],mo[0]],linesty=3
	endelse
	;
	; overplot fit
	if ngoo gt 5 then $
		oplot,wea[goo],ea[goo,1],thick=5,color=colordex('blue')
	;
	; check if we are making hardcopy
	if keyword_set(ps) then begin
		!p.font=font_store
		psclose
		kcwi_print_info,ppar,pre,'Plotting to ',psname + '.ps'
	endif
	;
	return
end
