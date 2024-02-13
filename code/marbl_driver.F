#include "cppdefs.opt"
#ifdef MARBL
      module marbl_driver
      use param, only: mynode,nt,ntrc_bio,isalt,itemp,Lm,Mm
      use marbl_interface, only: marbl_interface_class
#ifdef MARBL_DIAGS
      use MARBL_interface_public_types, only: marbl_diagnostics_type,
     &                                        marbl_saved_state_type
#endif      
      use dimensions, only: nz
      use get_bulk_wnd, only : uwnd, vwnd
      use bgc_forces, only: pco2air,pco2air_alt,dust,iron
      use surf_flux,  only : srflx
      use nc_read_write
      use scalars,    only : nstp,nnew,dt,iic,ntstart
#ifdef NOX_FORCING
      use bgc_forces, only: nox
#endif
#ifdef NHY_FORCING
      use bgc_forces, only:nhy
#endif      
      use ocean_vars, only: Hz, z_r, z_w

      implicit none

      type(MARBL_interface_class) :: marbl_instance
      integer :: nt_marbl ! number of marbl tracers      
      integer :: idx

!     The below are from the MOM driver, will decide if we can do things differently later
      integer,public :: u10_sqr_ind,sss_ind,sst_ind,ifrac_ind,dust_dep_ind,
     &  fe_dep_ind,nox_flux_ind,nhy_flux_ind,atmpress_ind,xco2_ind,xco2_alt_ind=-1
!     Same for these guys
      integer,public :: dustflux_ind,PAR_col_frac_ind,surf_shortwave_ind,potemp_ind,salinity_ind,
     & pressure_ind,fesedflux_ind,o2_scalef_ind,remin_scalef_ind=-1

#ifdef MARBL_DIAGS      
!     Keeping count of diagnostics:
      integer, public :: n_marbl_2d_sf_diags
      integer, public :: n_marbl_3d_sf_diags
      integer, public :: n_marbl_2d_it_diags
      integer, public :: n_marbl_3d_it_diags
      integer, public :: n_marbl_diags
#endif      
!     Saved state variables: (mimicking structure of bgc_ecosys_vars for bec2_diag arrays)
      integer :: nr_marbl_ss_2d,nr_marbl_ss_3d
      parameter( nr_marbl_ss_2d=3, nr_marbl_ss_3d=2)
!      real, dimension(GLOBAL_2D_ARRAY,nr_marbl_ss_2d) :: marbl_saved_state_2d
!      real, dimension(GLOBAL_2D_ARRAY,nz,nr_marbl_ss_3d) :: marbl_saved_state_3d      
      real,allocatable,dimension(:,:,:  ) :: marbl_saved_state_2d 
      real,allocatable,dimension(:,:,:,:) :: marbl_saved_state_3d
      character*72 :: vname_marbl_ss_2d(4,nr_marbl_ss_2d)
      character*72 :: vname_marbl_ss_3d(4,nr_marbl_ss_3d)
      integer :: printi = 4
      integer :: printj = 4
      integer :: printnode = 7
      
#include "bgc_tracers_indx.opt"
      
      contains
      subroutine marbldrv_configure_tracers(
     &     itot,t_vname,t_lname,t_units,t_tname,wrt_t,wrt_t_avg,t_ana_frc)

!      type(marbl_interface_class), intent(inout) :: marbl_instance
      character*42, dimension(nt), intent(inout) :: t_vname, t_units
      character*60, dimension(nt), intent(inout) :: t_lname
      character*47, dimension(nt), intent(inout) :: t_tname
      character(len=256)                         :: namelist_line!(1)
      integer                    , intent(inout) :: itot
      integer , dimension(nt)    , intent(inout) :: t_ana_frc
      logical , dimension(nt)    , intent(inout) :: wrt_t, wrt_t_avg
      real    , dimension(nz)                    :: dummy_array
      integer :: marbl_settings_in, read_status
      
      dummy_array(:)=1.0        ! Temporary measure until we can access an allocated Hz,z_w,z_r
      marbl_settings_in = 111
      
!     *** TRY TO OPEN NAMELIST FILE ***
      if (mynode>=0) then ! In MOM would be ==0 but this relies on "broadcast" (see below)
     ! read the marbl_in into buffer
         open(unit=marbl_settings_in, file='marbl_in', iostat=read_status)
         if (read_status .ne. 0) then !can't find namelist file, skip

            write(*, '(A, I0, 3A)') "IO WARNING ", read_status,
     &           "could not open namelist file : ", "marbl_in",
     &           ". attempting to proceed with default MARBL settings"
            
         else                   ! can find namelist file, read
!     *** READ NAMELIST FILE ***
            namelist_line = ''
            do                  !namelist line-by-line read
               read(marbl_settings_in,"(A)",iostat=read_status),
     &              namelist_line
!     MOM driver here calls `broadcast` to send info to other CPUs.
!     $CESM_ROOT/components/mom/MOM6/config_src/infra/FMS2/MOM_coms_infra.F90 > broadcast
                  
!     This in turn uses `mpp_broadcast`:
!     $CESM_ROOT/libraries/FMS/src/mpp/mpp.F90
                  
!     TODO: What is the ROMS equivalent?
!     ( It's "MPI_Bcast" )
               if (read_status .ne. 0) then
                  exit !loop
               else
                  call marbl_instance%put_setting(namelist_line)
                  if (mynode==0) print *,'marbl_in: ',namelist_line
               end if
               
            end do              ! namelist line-by-line read

            if (is_iostat_end(read_status)) then
               if (mynode==0) then
                  write(*, '(3A)') "Successfully read ","marbl_in",
     &                 " to end of file"
               end if
            else
               if (mynode==0) then
                  write(*, '(A, I0, 2A)') "IO ERROR ", read_status,
     &                 " : ERROR reading MARBL namelist file  ",
     &                 "marbl_in"
               end if
               error stop
            end if
         
            close(marbl_settings_in)
            print *, 'we successfully read and closed the file'
         endif
      endif
      print *, 'moving on'
!     * Now we have the settings read in, generate the marbl instance:
      
      call marbl_instance%init(gcm_num_levels=nz,
     &     gcm_num_PAR_subcols = 1,
     &     gcm_num_elements_surface_flux = 1,
     &     gcm_delta_z = dummy_array(:), !previously Hz
     &     gcm_zw = dummy_array(:), !previously z_w
     &     gcm_zt = dummy_array(:), !previously z_r
     &     lgcm_has_global_ops = .true.,
     &     unit_system_opt='mks')

      nt_marbl=size(marbl_instance%tracer_metadata)
      
!     20240124 - add a check that the number of tracers in MARBL_instance is NT:
      if ( nt_marbl .ne. ntrc_bio ) then
         write(*,'(7x,A,I4,A,I4,A,I4,A)')
     &        'ERROR: Allocated no. of MARBL tracers'
     &        ,ntrc_bio
     &        ,' does not match no. expected by MARBL: '
     &        ,nt_marbl
     &        ,' set ntrc_bio = ',nt_marbl
     &        ,' in param.opt and recompile'
         error stop 'ERROR reported from MARBL library'
      end if      
!     /20240124    
        
      call print_marbl_log(marbl_instance%StatusLog)
      call marbl_instance%StatusLog%erase()

      do idx=1,nt_marbl
         itot=itot+1         
         t_vname(itot)=trim(marbl_instance%tracer_metadata(idx)%short_name)
         t_lname(itot)=trim(marbl_instance%tracer_metadata(idx)%long_name)
         t_units(itot)=trim(marbl_instance%tracer_metadata(idx)%units)
         
         t_tname(itot)=''
         wrt_t     (itot)=.true.
         wrt_t_avg (itot)=.true.
         t_ana_frc( itot)=1

      end do

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!     Get the MARBL instance's surface flux forcing indices
      
      u10_sqr_ind = -1
      sss_ind = -1
      sst_ind = -1
      ifrac_ind = -1
      dust_dep_ind = -1
      fe_dep_ind = -1
      nox_flux_ind = -1
      nhy_flux_ind = -1
      atmpress_ind = -1
      xco2_ind = -1
      xco2_alt_ind = -1

      if (mynode==printnode) then 
         print *, 'Here are the SF forcings MARBL requested'
      end if
      do idx=1,size(marbl_instance%surface_flux_forcings)
         if (mynode==printnode) then
            print *, 'var: ', (trim(MARBL_instance%surface_flux_forcings(idx)%metadata%varname))
            print *, 'units:',(trim(MARBL_instance%surface_flux_forcings(idx)%metadata%field_units))
         end if
         
         select case (trim(MARBL_instance%surface_flux_forcings(idx)%metadata%varname))
         case('u10_sqr')
            u10_sqr_ind = idx
         case('sss')
            sss_ind = idx
         case('sst')
            sst_ind = idx
         case('Ice Fraction')
            ifrac_ind = idx
         case('Dust Flux')
            dust_dep_ind = idx
         case('Iron Flux')
            fe_dep_ind = idx
         case('NOx Flux')
            nox_flux_ind = idx
         case('NHy Flux')
            nhy_flux_ind = idx
         case('Atmospheric Pressure')
            atmpress_ind = idx
         case('xco2')
            xco2_ind = idx
         case('xco2_alt_co2')
            xco2_alt_ind = idx
         case DEFAULT
            print *, 'Additional forcing requested but not indexed: ',
     &           trim(MARBL_instance%surface_flux_forcings(idx)
     &           %metadata%varname)
         end select
      enddo

  !     ii. store all interior forcing indices
  ! This just creates indices (like the iNO3 etc. above) so that later in column_physics 
  ! we can check if theyre > 0 (i.e. that forcing exists) and populate the field 
      if (mynode==printnode) then
         print *, 'Here are the int. tend. forcings MARBL requested'
      end if
      
      do idx=1,size(MARBL_instance%interior_tendency_forcings)
    ! i. Check to see if this is a tracer restoring field or timescale
    ! ii. If not, should be one of the following:  
         if (mynode==printnode) then
            print *,'var: '  ,(trim(MARBL_instance%interior_tendency_forcings(idx)%metadata%varname))
            print *,'units: ',(trim(MARBL_instance%interior_tendency_forcings(idx)%metadata%field_units))            
         end if
   
         select case (trim(MARBL_instance%interior_tendency_forcings(idx)%metadata%varname))
         case('Dust Flux')
            dustflux_ind = idx
         case('PAR Column Fraction')
            PAR_col_frac_ind = idx
         case('Surface Shortwave')
            surf_shortwave_ind = idx
         case('Potential Temperature')
            potemp_ind = idx
         case('Salinity')
            salinity_ind = idx
         case('Pressure')
            pressure_ind = idx
         case('Iron Sediment Flux')
            fesedflux_ind = idx
         case('O2 Consumption Scale Factor')
            o2_scalef_ind = idx
         case('Particulate Remin Scale Factor')
            remin_scalef_ind = idx
         case DEFAULT
            print *, 'Additional forcing requested but not indexed: ',
     &           trim(MARBL_instance%interior_tendency_forcings(idx)
     &           %metadata%varname)
         end select
      enddo


      
      end subroutine marbldrv_configure_tracers

      subroutine marbldrv_configure_saved_state
      integer :: iss,nr_marbl_ss_2d_check,nr_marbl_ss_3d_check,i,j,k
      character(len=200) :: ss_varname

      
      ! Begin by checking whether our hardcoded values match MARBL expectations
      nr_marbl_ss_2d_check=0
      nr_marbl_ss_3d_check=0
!     go through both MARBL saved state types and check if fields are
!     2d or 3d one by one (calculate nr_marbl_ss_2d,nr_marbl_ss_3d):
!     2d and 3d surface flux saved state variable count:
            do iss=1,MARBL_instance%surface_flux_saved_state%saved_state_cnt
               if (MARBL_instance%surface_flux_saved_state%state(iss)%rank==2)
     &              then
                  nr_marbl_ss_2d_check=nr_marbl_ss_2d_check+1
               elseif (MARBL_instance%surface_flux_saved_state%state(iss)%rank==3)
     &                 then
                  nr_marbl_ss_3d_check=nr_marbl_ss_3d_check+1
               end if
            end do
!     2d and 2d interior tendency saved state variable count:
            do iss=1,MARBL_instance%interior_tendency_saved_state%saved_state_cnt
               if (MARBL_instance%interior_tendency_saved_state%state(iss)%rank==2)
     &              then
                  nr_marbl_ss_2d_check=nr_marbl_ss_2d_check+1
               elseif (MARBL_instance%interior_tendency_saved_state%state(iss)%rank==3)
     &                 then
                  nr_marbl_ss_3d_check=nr_marbl_ss_3d_check+1
               end if
            end do
!     Report error if counts don't match            
            if (nr_marbl_ss_2d/=nr_marbl_ss_2d_check) then
               write(*,'(7x,A,I4,A,I4,A)')
     &              'ERROR: Allocated no. of 2D marbl saved state vars '
     &              ,nr_marbl_ss_2d,
     &              ' does not match actual no. expected by MARBL: '
     &              ,nr_marbl_ss_2d_check
               error stop 'ERROR reported from MARBL library'
            elseif (nr_marbl_ss_3d/=nr_marbl_ss_3d_check) then
               write(*,'(7x,A,I4,A,I4,A)')
     &              'ERROR: Allocated no. of 3D marbl saved state vars '               
     &              ,nr_marbl_ss_3d,
     &              ' does not match actual no. expected by MARBL: '
     &              ,nr_marbl_ss_3d_check
               error stop 'ERROR reported from MARBL library'
            end if
               

!     Now provide metadata:
            ! surface flux saved state metadata (all 2D variables currently)
            do iss=1,MARBL_instance%surface_flux_saved_state%saved_state_cnt
               write(ss_varname, "(2A)")
     &              "MARBL_",
     &              trim(MARBL_instance%surface_flux_saved_state%state(iss)%short_name)
               vname_marbl_ss_2d(1,iss)=trim(ss_varname)
               vname_marbl_ss_2d(2,iss)=
     &              trim(MARBL_instance%surface_flux_saved_state%state(iss)%long_name)
               vname_marbl_ss_2d(3,iss)=
     &              trim(MARBL_instance%surface_flux_saved_state%state(iss)%units)
               vname_marbl_ss_2d(4,iss)='  '
               
               if (mynode==printnode) then
                  print *, 'MARBL SF SAVED STATE VARIABLE ',
     &                 trim(vname_marbl_ss_2d(1,iss)),'  ',
     &                 trim(vname_marbl_ss_2d(2,iss)),'  ',
     &                 trim(vname_marbl_ss_2d(3,iss))
               end if
               
            end do
            ! interior tendency saved state metadata (all 3D variables currently)
            do iss=1,MARBL_instance%interior_tendency_saved_state%saved_state_cnt
               write(ss_varname, "(2A)")
     &              "MARBL_",
     &              trim(MARBL_instance%interior_tendency_saved_state%state(iss)%short_name)
               vname_marbl_ss_3d(1,iss)=trim(ss_varname)
               vname_marbl_ss_3d(2,iss)=
     &              trim(MARBL_instance%interior_tendency_saved_state%state(iss)%long_name)
               vname_marbl_ss_3d(3,iss)=
     &              trim(MARBL_instance%interior_tendency_saved_state%state(iss)%units)
               

               if (mynode==printnode) then
                  print *, 'MARBL IT SAVED STATE VARIABLE ',
     &                 trim(vname_marbl_ss_3d(1,iss)),'  ',
     &                 trim(vname_marbl_ss_3d(2,iss)),'  ',
     &                 trim(vname_marbl_ss_3d(3,iss))  
               end if
                  
            end do
               
!     allocate arrays for 2d and 3d saved state variables      
            allocate( marbl_saved_state_2d(GLOBAL_2D_ARRAY,nr_marbl_ss_2d))
            allocate( marbl_saved_state_3d(GLOBAL_2D_ARRAY,nz,nr_marbl_ss_3d))
            if (mynode==printnode) then
               write(*,'(7x,A,I4,I4)') 'MARBL saved state allocation ::',
     &              nr_marbl_ss_2d,nr_marbl_ss_3d !3,2
            end if
            
            
      end subroutine marbldrv_configure_saved_state

!      subroutine marbldrv_wrt_rst_ss(ncid,start)
!!     write saved state to restart file
!!     restart includes bgc tracers for simplicity
!      implicit none
!      ! inputs
!      integer, intent(in) :: ncid
!      integer,dimension(:),intent(in) :: start
!      ! local
!      integer :: iss
!      do itrc=1,nr_marbl_ss_2d
!         call ncwrite(ncid,vname_marbl_ss_2d(1,iss),
!     &        marbl_saved_state_2d(i0:i1,j0:j1,itrc),start)
!      enddo
!      do itrc=1,nr_marbl_ss_3d
!         call ncwrite(ncid,vname_marbl_ss_3d(1,iss),
!     &        marbl_saved_state_2d(i0:i1,j0:j1,:,itrc),start)
!      enddo
!
!      end subroutine marbldrv_wrt_rst_ss  !]

#ifdef MARBL_DIAGS
      subroutine marbldrv_configure_diagnostics(
     &     vname_bec2_diag_2d,vname_bec2_diag_3d,
     &     wrt_bec2_diag_2d,wrt_bec2_diag_3d)

      character*72, dimension(:,:), intent(inout) :: vname_bec2_diag_2d
      character*72, dimension(:,:), intent(inout) :: vname_bec2_diag_3d
      logical,      dimension(:),   intent(inout) :: wrt_bec2_diag_2d
      logical,      dimension(:),   intent(inout) :: wrt_bec2_diag_3d
      integer :: m,diagidx2d,diagidx3d
      ! ---------------------------------------------
      n_marbl_2d_sf_diags=0
      n_marbl_3d_sf_diags=0
      n_marbl_2d_it_diags=0
      n_marbl_3d_it_diags=0
      n_marbl_diags=0
      diagidx2d=1
      diagidx3d=1
      
      if (mynode==printnode)  print *, 'MARBL SURFACE FLUX DIAGNOSTICS'
      do m=1,size(MARBL_instance%surface_flux_diags%diags)
         n_marbl_diags=n_marbl_diags+1
         if (trim(MARBL_instance%surface_flux_diags%diags(m)
     &        %vertical_grid) .eq. "none") then ! 2D field
            n_marbl_2d_sf_diags=n_marbl_2d_sf_diags+1
         else
            n_marbl_3d_sf_diags=n_marbl_3d_sf_diags+1
         end if
      end do
      do m=1,size(MARBL_instance%interior_tendency_diags%diags)
         n_marbl_diags=n_marbl_diags+1
         if (trim(MARBL_instance%interior_tendency_diags%diags(m)
     &        %vertical_grid) .eq. "none") then ! 2D field
            n_marbl_2d_it_diags=n_marbl_2d_it_diags+1
         else
            n_marbl_3d_it_diags=n_marbl_3d_it_diags+1
         end if
      end do
! ... so we can check if it matches the number allocated by ROMS ...
      if ( size(vname_bec2_diag_2d(1,:)) .ne.
     &     (n_marbl_2d_sf_diags+n_marbl_2d_it_diags) ) then
         write(*,'(7x,A,I4,A,I4,A,I4,A)')
     &        'ERROR: Allocated no. of 2D BGC diagnostics: '
     &        ,size(vname_bec2_diag_2d(1,:))
     &        ,' does not match no. expected by MARBL: '
     &        ,(n_marbl_2d_sf_diags+n_marbl_2d_it_diags)
     &        ,'. Set nr_bec2_diag_2d = '
     &        ,(n_marbl_2d_sf_diags+n_marbl_2d_it_diags)
     &        ,' in bgc_ecosys_vars.F and recompile'
         error stop 'ERROR reported from MARBL library'
      elseif ( size(vname_bec2_diag_3d(1,:)) .ne.
     &        (n_marbl_3d_sf_diags+n_marbl_3d_it_diags) ) then
         write(*,'(7x,A,I4,A,I4,A,I4,A)')
     &        'ERROR: Allocated no. of 3D BGC diagnostics: '
     &        ,size(vname_bec2_diag_3d(1,:))
     &        ,' does not match no. expected by MARBL: '
     &        ,(n_marbl_3d_sf_diags+n_marbl_3d_it_diags)
     &        ,'. Set nr_bec2_diag_3d = '
     &        ,(n_marbl_3d_sf_diags+n_marbl_3d_it_diags)
     &        ,' in bgc_ecosys_vars.F and recompile'
         error stop 'ERROR reported from MARBL library'
      end if
!     ...  end of check
! NOTE: need to set these values in an opt file or elsewhere but not bgc_ecosys_vars
      
!     Populate BGC diagnostics metadata arrays in ROMS using MARBL
      if (mynode==printnode)  print *, 'MARBL SURFACE FLUX DIAGNOSTICS'
      do m=1,size(MARBL_instance%surface_flux_diags%diags)
         if (trim(MARBL_instance%surface_flux_diags%diags(m)%vertical_grid) .eq. "none") then ! 2D field
            vname_bec2_diag_2d(1,idx2d)=
     &           trim(MARBL_instance%surface_flux_diags%diags(m)%short_name)
            vname_bec2_diag_2d(2,diagidx2d)=
     &           trim(MARBL_instance%surface_flux_diags%diags(m)%long_name)
            vname_bec2_diag_2d(3,diagidx2d)=
     &           trim(MARBL_instance%surface_flux_diags%diags(m)%units)
            vname_bec2_diag_2d(4,diagidx2d)='  '
            wrt_bec2_diag_2d(diagidx2d)=.true.

            diagidx2d=diagidx2d+1
         else                   ! 3D field
            ! There are no 3D surface flux diags, this is for generalisation purposes
            vname_bec2_diag_3d(1,diagidx3d)=
     &           trim(MARBL_instance%surface_flux_diags%diags(m)%short_name)
            vname_bec2_diag_3d(2,diagidx3d)=
     &           trim(MARBL_instance%surface_flux_diags%diags(m)%long_name)
            vname_bec2_diag_3d(3,diagidx3d)=
     &           trim(MARBL_instance%surface_flux_diags%diags(m)%units)
            vname_bec2_diag_3d(4,diagidx3d)='  '
            wrt_bec2_diag_3d(diagidx3d)=.true.
!
            diagidx3d=diagidx3d+1
         end if
      end do

      if (mynode==printnode) print *,
     &     'MARBL INTERIOR TENDENCY DIAGNOSTICS'
      do m=1,size(MARBL_instance%interior_tendency_diags%diags)
         if (trim(MARBL_instance%interior_tendency_diags%diags(m)%vertical_grid) .eq. "none") then ! 2D field
            vname_bec2_diag_2d(1,diagidx2d)=
     &           trim(MARBL_instance%interior_tendency_diags%diags(m)%short_name)
            vname_bec2_diag_2d(2,diagidx2d)=
     &           trim(MARBL_instance%interior_tendency_diags%diags(m)%long_name)
            vname_bec2_diag_2d(3,diagidx2d)=
     &           trim(MARBL_instance%interior_tendency_diags%diags(m)%units)
               vname_bec2_diag_2d(4,diagidx2d)='  '
               wrt_bec2_diag_2d(diagidx2d)=.true.

            diagidx2d=diagidx2d+1
         else                   ! 3D field

            vname_bec2_diag_3d(1,diagidx3d)=
     &           trim(MARBL_instance%interior_tendency_diags%diags(m)%short_name)
            vname_bec2_diag_3d(2,diagidx3d)=
     &           trim(MARBL_instance%interior_tendency_diags%diags(m)%long_name)
            vname_bec2_diag_3d(3,diagidx3d)=
     &            trim(MARBL_instance%interior_tendency_diags%diags(m)%units)
            vname_bec2_diag_3d(4,diagidx3d)='  '
            wrt_bec2_diag_3d(diagidx3d)=.true.

            diagidx3d=diagidx3d+1
         end if
      end do
      if (mynode==printnode) then
         print *, 'number of 2D marbl diags', n_marbl_2d_sf_diags+n_marbl_2d_it_diags
         print *, 'number of 3D marbl diags', n_marbl_3d_sf_diags+n_marbl_3d_it_diags
      end if
!     -----------------------------------------------------------------
! Initialise MARBL diagnostics
!     In bgc_2Ddiagnostics.opt we have
!     - this_diags_idx=1 !(e.g.)
!     - vname_bec2_diag_2d(1,this_diags_idx)='SHORT_NAME'
!     - vname_bec2_diag_2d(2,this_diags_idx)='LONG_NAME'
!     - vname_bec2_diag_2d(3,this_diags_idx)='<UNITS>'
!     - vname_bec2_diag_2d(4,this_diags_idx)='  ' !(just two spaces?)
!     - wrt_bec2_diag_2d(this_diags_idx) = .false. ! (choosing whether to write)
!     -----------------------------------------------------------------
      
      end subroutine marbldrv_configure_diagnostics
#endif /* MARBL_DIAGS */
      
      subroutine marbldrv_column_physics(istr,iend,jstr,jend,tracer_array
     &     ,landmask
#ifdef MARBL_DIAGS      
     &     ,diag_array_2d,diag_array_3d
#endif
     &     ,marbl_ss_2d,marbl_ss_3d
     &) 


! Still TODO
!     - u10_sqr is currently taken from bulk_frc, but if bulk_frc is off,
!     ROMS current bgc_ecosys_bec2.F has a "WS" SR that calcs from scratch
!     We don't do this here. BULK_FRC is needed.
      
      integer, intent(in) ::  istr,jstr,iend,jend
      real, dimension(:,:,:,:,:), intent(inout) :: tracer_array
      logical, dimension(      :,:), intent(in)    :: landmask      
#ifdef MARBL_DIAGS      
      real, dimension(:,:,:), intent(inout) :: diag_array_2d
      real, dimension(:,:,:,:), intent(inout) :: diag_array_3d
      integer :: diagidx2d,diagidx3d
#endif
      real, dimension(:,:,:), intent(inout) :: marbl_ss_2d
      real, dimension(:,:,:,:),intent(inout) :: marbl_ss_3d

      integer :: i,j,k,m
      logical :: sf_verb = .false. ! Print example SF values to stdout during loop
      integer :: tmpind ! a placeholder index for lazy code copypaste
      tmpind = 0

      do j=jstr,jend
         do i=istr,iend
            if ( landmask(i,j) .eqv. .false. ) cycle            
!     ################################################################################
            ! POPULATE MARBL SURFACE_FLUX_FORCINGS
!     ################################################################################

!     -------------------------------------------------------------------------------- SSS!
!     (psu)
!     called "SSSS" in bgc_ecosys_bec2.F
            if (sss_ind > 0) then
               marbl_instance%surface_flux_forcings(sss_ind)%field_0d(1)
     &              =tracer_array(i,j,nz,nnew,isalt)
               if (sf_verb) call sf_test_print(sss_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- SST!!
!     (degC)
            if (sst_ind > 0) then
               marbl_instance%surface_flux_forcings(sst_ind)%field_0d(1)
     &              =tracer_array(i,j,nz,nnew,itemp)
               if (sf_verb) call sf_test_print(sst_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- ifrac
!     (unitless) - NO ICE IN ROMS SO SET TO 0
!     "FICE_USED" in bgc_ecosys_bec2.F - "ifrac" comes from bgc_ecosys_vars
            if (ifrac_ind > 0) then

               marbl_instance%surface_flux_forcings(ifrac_ind)%field_0d(1)=0
!     &              ifrac(i,j)
               if (sf_verb) call sf_test_print(ifrac_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- wspd^2
!     (m2/s2)
            if (u10_sqr_ind > 0) then
               marbl_instance%surface_flux_forcings(u10_sqr_ind)%field_0d(1)=
     &               (uwnd(i,j)**2) + (vwnd(i,j)**2)

               if (sf_verb) call sf_test_print(u10_sqr_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- press!!
!     (MARBL: atm, ROMS: atm [bgc_ecosys_bec2])
!     "AP_USED" in bgc_ecosys_bec2.F, "press" comes from bgc_ecosys_vars
!     Just being set to 1 right now
            
            if (atmpress_ind > 0) then
            marbl_instance%surface_flux_forcings(atmpress_ind)%field_0d(1)=1.
!     &              press(i,j)
            if (sf_verb) call sf_test_print(atmpress_ind,i,j)            
            end if 
!     -------------------------------------------------------------------------------- pco2
!     (MARBL: ppmv; ROMS: ppm)
!     "XCO2" in bgc_ecosys_bec2.F, "pco2air" comes from bgc_forces
            if (xco2_ind > 0) then
               marbl_instance%surface_flux_forcings(xco2_ind)%field_0d(1)=
     &              pco2air(i,j)
               if (sf_verb) call sf_test_print(xco2_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- altpco2 !!
!     (MARBL: ppmv; ROMS: none)
            if (xco2_alt_ind > 0) then
               marbl_instance%surface_flux_forcings(xco2_alt_ind)%field_0d(1)=
     &              pco2air_alt(i,j)
               if (sf_verb) call sf_test_print(xco2_alt_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- dust !!
!     (MARBL: kg/m^2/s ; ROMS: kg/m^2/s
!     called "dust" in bgc_forces.F

            if (dust_dep_ind > 0) then
               marbl_instance%surface_flux_forcings(dust_dep_ind)%field_0d(1)
     &              = dust(i,j)
               if (sf_verb) call sf_test_print(dust_dep_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- iron
!     (MARBL: mmol/m^2/s; ROMS: nmol/cm^2/s)
            if (fe_dep_ind > 0) then
               marbl_instance%surface_flux_forcings(fe_dep_ind)%field_0d(1)=
     &              iron(i,j)*0.01 ! nmol/cm2/s -> mmol/m2/s
               if (sf_verb) call sf_test_print(fe_dep_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- nox !!!
!     (MARBL: mmol/m^2/s; ROMS: kg/m^2/s)
!     X,Y => any number of oxygen/hydrogen
#ifdef NOX_FORCING
            if (nox_flux_ind > 0) then
               marbl_instance%surface_flux_forcings(nox_flux_ind)%field_0d(1)=               
     &              nox(i,j)*71394.200220751 ! kg(N)/m2/s -> mmol/m2/s
!     &              1e-13 * 71394.200220751 ! just setting to a nonzero value for now               
               if (sf_verb) call sf_test_print(nox_flux_ind,i,j)
            end if
#endif            
!     -------------------------------------------------------------------------------- nhy !!!
!     (MARBL: mmol/m^2/s, ROMS: hard to tell? in bgc_ecosys_bec2 IS kg[/m2/s?])
#ifdef NHY_FORCING 
            if (nhy_flux_ind > 0) then
               marbl_instance%surface_flux_forcings(nhy_flux_ind)%field_0d(1)=
     &              nhy(i,j)*71394.200220751 ! kg(N)/m2/s -> mmol/m2/s               
!     &              1e-13 * 71394.200220751 ! just setting to a nonzero value for now               
               if (sf_verb) call sf_test_print(nhy_flux_ind,i,j)
            end if
#endif
!     --------------------------------------------------------------------------------
            
            do m=1,nt_marbl
     !           Copy ROMS tracers to MARBL _but set to 0 if negative
     !           Currently inactive
     !           if ( tracer_array(i,j,nz,nnew, m+(NT-nt_marbl)) .lt. 0 )
     ! &              then
     !              marbl_instance%tracers_at_surface(1,m)=0.               
     !           else
     !              marbl_instance%tracers_at_surface(1,m)=
     ! &                 tracer_array(i,j,nz,nnew, m+(NT-nt_marbl))
     !           end if

               marbl_instance%tracers_at_surface(1,m)=
     &                 tracer_array(i,j,nz,nnew, m+(NT-nt_marbl))
               
               if ( (i==printi) .and. (j==printj)
     &              .and. (mynode==printnode) .and. (sf_verb) ) then
                  print *, 'We just set surface ',
     &                 (trim(MARBL_instance%tracer_metadata(m)%short_name)),
     &                 ' as ',marbl_instance%tracers_at_surface(1,m),
     &                 (trim(MARBL_instance%tracer_metadata(m)%units))
               end if
!
            end do
!     --------------------------------------------------------------------------------

!     * surface flux saved state
!     just set to 0 for now
!            do m=1,size(MARBL_instance%surface_flux_saved_state%state)
!               if ((mynode==printnode) .and. (j==printj) .and. (i==printi)) then
!                  print *, 'SF saved state: ',
!     &                 MARBL_instance%surface_flux_saved_state%state(m)%long_name
!               end if               
!               MARBL_instance%surface_flux_saved_state%state(m)%field_2d(1)
!     &              =0.
!            enddo
!     20240117 - Currently all MARBL SF saved state vars are 2D, all IT saved state vars are 3D
            do m=1,MARBL_instance%surface_flux_saved_state%saved_state_cnt
!               if ( (mynode==printnode) .and. (j==printj) .and. (i==printi) ) then
!                  print *, 'POPULATING SF saved state: ',
!     &                 trim(MARBL_instance%surface_flux_saved_state%state(m)%long_name)
!               end if
               MARBL_instance%surface_flux_saved_state%state(m)%field_2d(1)
     &              =marbl_ss_2d(i,j,m) !0.


               
               if ( (i==printi) .and. (j==printj)
     &              .and. (mynode==printnode) .and. (sf_verb) ) then
                  print *, 'We just set surface ',
     &                 trim(MARBL_instance%surface_flux_saved_state%
     &                 state(m)%short_name),
     &                 ' as ',MARBL_instance%surface_flux_saved_state%
     &                 state(m)%field_2d(1),
     &                 trim(MARBL_instance%surface_flux_saved_state%
     &                 state(m)%units)
               end if
               
            end do
               
!/20240117
            
!     ################################################################################
!     CALL SURFACE_FLUX_COMPUTE()

            if ( (mynode==printnode) .and. (sf_verb) .and.
     &           (j==printj) .and. (i==printi)) then
               print *, "calling surface flux compute..."
            end if
            
            call marbl_instance%surface_flux_compute()
            if ( (mynode==printnode) .and. (sf_verb) .and.
     &           (j==printj) .and. (i==printi) ) then
               print *, "calling surface flux compute... done"
            end if

            if (marbl_instance%StatusLog%labort_marbl) then
               print *, 'abort during surface flux compute'
               call marbl_instance%StatusLog%log_error_trace(
     &              "marbl_instance%surface_flux_compute()",
     &              "MARBL_tracers_column_physics")
               call print_marbl_log(marbl_instance%StatusLog,i,j)
            end if

            !call print_marbl_log(marbl_instance%StatusLog)            
            call marbl_instance%StatusLog%erase()

!     ################################################################################
!     POPULATE/UPDATE SAVED STATE ARRAY
!     20240117 - Currently all MARBL SF saved state vars are 2D, all IT saved state vars are 3D

            do m=1,MARBL_instance%surface_flux_saved_state%saved_state_cnt
               marbl_ss_2d(i,j,m)=
     &              MARBL_instance%surface_flux_saved_state%state(m)%field_2d(1)
            end do
            
!     POPULATE DIAGNOSTICS ARRAY
#ifdef MARBL_DIAGS
            diagidx2d=1
            diagidx3d=1
            do m=1,size(MARBL_instance%surface_flux_diags%diags)
               if (trim(MARBL_instance%surface_flux_diags%diags(m
     &              )%vertical_grid) .eq. "none") then ! 2D field
                  
!                  if ((mynode==printnode) .and. (i==printi) .and. (j==printj) )
!     &                 print *, 'SF DIAG 2D ',diagidx2d,
!     &                 trim(MARBL_instance%surface_flux_diags%diags(m)%short_name)
!                  
                  diag_array_2d(i,j,diagidx2d)=
     &                 real(MARBL_instance%surface_flux_diags%diags(m)%field_2d(1))
                  diagidx2d=diagidx2d+1
               else             ! 3D field

!                  if ((mynode==printnode) .and. (i==printi) .and. (j==printj) )
!     &                 print *, 'SF DIAG 3D ',diagidx3d,
!     &                 trim(MARBL_instance%surface_flux_diags%diags(m)%short_name)                  
                  
                  diag_array_3d(i,j,:,diagidx3d)=
     &                 real(MARBL_instance%surface_flux_diags%diags(m)%field_3d(1,:))
                  diagidx3d=diagidx3d+1
               end if
            end do
#endif       
           
         end do   ! j=jstr,jend
      end do      ! i=istr,iend
      
      
!     - MOM VERSION "applies surface fluxes via vertical diffusion"
!     ... uses a series of MOM subroutines to do this. 

!     ################################################################################
!      POPULATE INTERIOR TENDENCY FORCINGS

      do j=jstr,jend
         do i=istr,iend
            if (landmask(i,j) .eqv. .false. ) cycle
            
!     !i.  update domain
!     re. interface depth MOM treats first top interface as index 0 so doesn't explicitly store : check ROMS behaviour
            
            MARBL_instance%domain%zw(:)      = -z_w(i,j,nz-1:0:-1) ! bottom interface depth
            MARBL_instance%domain%zt(:)      = -z_r(i,j,nz:1:-1)  ! centre depth
            MARBL_instance%domain%delta_z(:) = Hz( i,j,nz:1:-1) ! thickness
            MARBL_instance%domain%kmt        = nz
            
!     ################################################################################
            if (dustflux_ind > 0) then
               MARBL_instance%interior_tendency_forcings(dustflux_ind)%field_0d(1)=
     &              dust(i,j)
            end if
!     -------------------------------------------------------------------------------- 
!     The 1d of this is not column levels but number of ice categories:
!     We have 1 (open ocean) so PAR and surf SW statements below are unused
            if (PAR_col_frac_ind > 0) then
               !MARBL_instance%interior_tendency_forcings(PAR_col_frac_ind)%field_1d(1,:)=
            end if
!     -------------------------------------------------------------------------------- 
            if (surf_shortwave_ind > 0) then               
               MARBL_instance%interior_tendency_forcings(surf_shortwave_ind)%field_1d(1,1)=
     &              srflx(i,j)
!     Set to whatever the local surface shortwave is
            end if
!     -------------------------------------------------------------------------------- 
            if (potemp_ind > 0) then
               MARBL_instance%interior_tendency_forcings(potemp_ind)%field_1d(1,:)
     &              =tracer_array(i,j,nz:1:-1,nnew,itemp)
               if (sf_verb) call if_test_print(potemp_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- FLIP
            if (salinity_ind > 0) then
               MARBL_instance%interior_tendency_forcings(salinity_ind)%field_1d(1,:)
     &              =tracer_array(i,j,nz:1:-1,nnew,isalt)
               if (sf_verb) call if_test_print(salinity_ind,i,j)               
            end if
!     -------------------------------------------------------------------------------- FLIP
            if (pressure_ind > 0) then
               MARBL_instance%interior_tendency_forcings(pressure_ind)%field_1d(1,:)=
     &              -z_r(i,j,nz:1:-1)*0.1
!     &              =p(i,j,nz:1:-1)
               if (sf_verb) call if_test_print(pressure_ind,i,j)
            end if
!     -------------------------------------------------------------------------------- 
!     This is based on a 1/60* bathymetry dataset, a sort of subgrid-scale way of putting
!     iron where the bed would be in reality even where the bed is unresolved
!     by suspending it at the equivalent point in the water column

!     >>> We'll probably come back to this <<<
            
            if (fesedflux_ind > 0) then
               MARBL_instance%interior_tendency_forcings(fesedflux_ind)%field_1d(1,:)=0.
               if (sf_verb) call if_test_print(fesedflux_ind,i,j)
            end if
!     --------------------------------------------------------------------------------
!     o2_scalef_ind and remin_scalef_ind  are to deal with OMZs in CESM2 and aren't set here

!     * Column tracers
            do m=1,nt_marbl

!           Set marbl tracers to 0 if ROMS version is negative
!           [Currently inactive]
     !           do k=1,nz
     !              if ( tracer_array(i,j,nz+1-k,nnew, m+(NT-nt_marbl))
     ! &                 .lt. 0 ) then
     !                  marbl_instance%tracers(m,k)=0.
     !              else
     !                 marbl_instance%tracers(m,k)=
     ! &                    tracer_array(i,j,nz+1-k,nnew, m+(NT-nt_marbl))
     !              end if
     !           end do
               marbl_instance%tracers(m,:)=                  
     &              tracer_array(i,j,nz:1:-1,nnew, m+(NT-nt_marbl) )
               
               if ( (i==printi) .and. (j==printj)
     &              .and. (mynode==printnode) .and. (sf_verb) ) then
                  print *, 'We just set bottom ',
     &                 (trim(MARBL_instance%tracer_metadata(m)%short_name)),
     &                 ' as ',marbl_instance%tracers(m,nz),
     &                 (trim(MARBL_instance%tracer_metadata(m)%units))                  
               end if

            end do

!     * Interior tendency saved state
!     Currently just set to 0 - TODO
            
!            do m=1,size(MARBL_instance%interior_tendency_saved_state%state)
!               if ((mynode==printnode) .and. (j==printj) .and. (i==printi)) then
!                  print *, 'IT saved state: ',
!     &                 MARBL_instance%interior_tendency_saved_state%state(m)%long_name
!               end if
!               MARBL_instance%interior_tendency_saved_state%state(m)%field_3d(:,1)
!     &              =0.
!            enddo            
!     20240117 - Currently all MARBL SF saved state vars are 2D, all IT saved state vars are 3D            
            do m=1,MARBL_instance%interior_tendency_saved_state%saved_state_cnt
!     if ( (mynode==printnode) .and. (i==printi) .and. (j==printj) ) then
!                     print *, 'POPULATING IT saved state: ',
!     &                trim(MARBL_instance%interior_tendency_saved_state%state(m)%long_name)
!                  end if
               
               MARBL_instance%interior_tendency_saved_state%state(m)%field_3d(:,1)
     &              =marbl_ss_3d(i,j,nz:1:-1,m) !0.
!     if ((m==1) .and. (iic==4854)) then
!               if ((m==1) .and. (mynode==0) .and.
!     &              (i==4) .and. (j==4)) then
!                  print *,'STEP=',iic
!     &                 ,',i=',i,',j=',j,',mynode=',mynode!,',MAX '
!     &                 ,trim(MARBL_instance%interior_tendency_saved_state%state(m)%long_name)
!     &                 ,': '
!     &                 ,(MARBL_instance%interior_tendency_saved_state%state(m)%field_3d(:,1))               
!     &                 ,maxval(MARBL_instance%interior_tendency_saved_state%state(m)%field_3d(:,1))
!               end if
!               if (m==1) then
!                  print *,'STEP=',iic
!     &                 ,',i=',i,',j=',j,',mynode=',mynode,',MIN '
!     &                 ,trim(MARBL_instance%interior_tendency_saved_state%state(m)%long_name)
!     &                 ,': '
!     &                 ,(MARBL_instance%interior_tendency_saved_state%state(m)%field_3d(:,1))               
!     &                 ,minval(MARBL_instance%interior_tendency_saved_state%state(m)%field_3d(:,1))
!               end if

               
               if ( (i==printi) .and. (j==printj)
     &              .and. (mynode==printnode) .and. (sf_verb) ) then
                  print *, 'We just set bottom ',
     &                 trim(MARBL_instance%
     &                 interior_tendency_saved_state%state(m)%long_name)
     &                 ,' as ',marbl_instance%
     &                 interior_tendency_saved_state%state(m)%field_3d(nz,1)
     &                 ,trim(MARBL_instance%interior_tendency_saved_state%state(m)%units) 
               end if
               
            end do    
!/20240117

!     * bottom fluxes
            marbl_instance%bot_flux_to_tend(:)=0.
            marbl_instance%bot_flux_to_tend(nz)=
     &           1./MARBL_instance%domain%delta_z(nz) 
            
            
!     * Interior tendency compute
            call marbl_instance%interior_tendency_compute()

            if (marbl_instance%StatusLog%labort_marbl) then
               print *, 'abort during interior tendency compute'
               call marbl_instance%StatusLog%log_error_trace(
     &             "marbl_instance%interior_tendency_compute()",
     &              "MARBL_tracers_column_physics")
               call print_marbl_log(marbl_instance%StatusLog,i,j)
               !error stop 'ERROR reported from MARBL library'                           
            end if
!            call print_marbl_log(marbl_instance%StatusLog,i,j)
            call marbl_instance%StatusLog%erase()
            
           
!     * Apply calculated increments:

            do m=1,nt_marbl
               tracer_array(i,j,:,nnew, m+(NT-nt_marbl) ) =
     &              tracer_array(i,j,:,nnew, m+(NT-nt_marbl) ) +
     &              marbl_instance%interior_tendencies(m,nz:1:-1)*dt
            end do
            
!     * need to update saved state after IT compute

            do m=1,MARBL_instance%interior_tendency_saved_state%saved_state_cnt
               marbl_ss_3d(i,j,:,m)=
     &             MARBL_instance%interior_tendency_saved_state%state(m)%field_3d(nz:1:-1,1)
            end do    

!     ################################################################################
!     POPULATE DIAGNOSTICS ARRAY
#ifdef MARBL_DIAGS
            diagidx2d=n_marbl_2d_sf_diags+1
            diagidx3d=n_marbl_3d_sf_diags+1
            
            do m=1,size(MARBL_instance%interior_tendency_diags%diags)
               if (trim(MARBL_instance%interior_tendency_diags%diags(m
     &              )%vertical_grid) .eq. "none") then ! 2D field

!                  if ((mynode==printnode) .and. (i==printi) .and. (j==printj) )
!     &                 print *, 'IT DIAG 2D ',diagidx2d,
!     &                 trim(MARBL_instance%interior_tendency_diags%diags(m)%short_name)
                  
                  diag_array_2d(i,j,diagidx2d)=
     &                 real(MARBL_instance%interior_tendency_diags%diags(m)%field_2d(1))
                  diagidx2d=diagidx2d+1
               else             ! 3D field

!                  if ((mynode==printnode) .and. (i==printi) .and. (j==printj) )
!     &                 print *, 'IT DIAG 3D ',diagidx3d,
!     &                 trim(MARBL_instance%interior_tendency_diags%diags(m)%short_name)

                  diag_array_3d(i,j,:,diagidx3d)=
     &                 real(MARBL_instance%interior_tendency_diags%diags(m)%field_3d(:,1))
                  diagidx3d=diagidx3d+1
               end if
            end do
#endif       


            
         end do                 !j=jstr,jend
      end do                    ! i=istr,iend


      
      
      end subroutine marbldrv_column_physics

      subroutine print_marbl_log(log_to_print,i,j)
      
      use marbl_logging, only: marbl_status_log_entry_type, marbl_log_type

      class(marbl_log_type),           intent(in) :: log_to_print
      integer              , optional, intent(in) :: i,j

      character(len=256)             :: message_prefix,message_location,log_message
      type(marbl_status_log_entry_type), pointer :: marbl_status_log_pointer
      marbl_status_log_pointer => log_to_print%FullLog

!     ###############################################################################

      
      do while (associated(marbl_status_log_pointer))
         !print *, marbl_status_log_pointer%lonly_master_writes
         
         write(message_prefix, "(A,I0,A)") "Task ",mynode,")"
      
! Check we are either on principal cpu OR all cpus can write:
         if ((.not. marbl_status_log_pointer%lonly_master_writes) .or.
     &        (mynode==printnode)) then
!     check if we know the location of this log message
            if (marbl_status_log_pointer%ElementInd .gt. 0) then
               if (present(i) .and. present(j)) then
                  write(message_location, "(A,I0,A,I0,A,I0)")
     &                 "Message from (i,j) (", i,",",j,") at level ",
     &                 marbl_status_log_pointer%ElementInd
               else
                  write(message_location, "(A)")
     &                 "grid cell responsible for message unknown"
               end if ! i,j present
               

!     If on principal CPU, don't apply prefix stating task #
               if (mynode==printnode) then
                  write(log_message,"(A)") trim(message_location)
               else
                  write(log_message,"(A,1X,A)")
     &                 trim(message_prefix), trim(message_location)
               end if           ! (mynode==printnode)
               print *, trim(log_message)
            end if              ! (ElementInd > 0)
            
            if (mynode==printnode) then
               write(log_message,"(A)")
     &              trim(marbl_status_log_pointer%LogMessage)
            else
               write(log_message,"(A,1X,A)")
     &              trim(message_prefix),
     &              trim(marbl_status_log_pointer%LogMessage)
            end if              ! (mynode==printnode)
            print *, trim(log_message)
         end if ! mynode 0 or not master task only
            
            marbl_status_log_pointer => marbl_status_log_pointer%next
      end do                    ! while(associated(marbl_status_log_pointer))
      if (log_to_print%labort_marbl) then
         error stop 'ERROR reported from MARBL library'            
      end if
         
         
      
      end subroutine print_marbl_log

      
      subroutine sf_test_print(ind,i,j)
      integer, intent(in) :: i,j,ind

      if (j==printj) then
         if (i==printi) then
            if (mynode==printnode) then
               print *, 'We just set ',
     &              (trim(MARBL_instance%surface_flux_forcings(ind)%metadata%varname)),
     &              ' as ',marbl_instance%surface_flux_forcings(ind)%field_0d(1),
     &              (trim(MARBL_instance%surface_flux_forcings(ind)%metadata%field_units))
            end if                     
         end if
      end if                              
      end subroutine sf_test_print

      subroutine if_test_print(ind,i,j)
      integer, intent(in) :: i,j,ind

      if (j==printj) then
         if (i==printi) then
            if (mynode==printnode) then
               print *, 'We just set bottom ',
     &              (trim(MARBL_instance%interior_tendency_forcings(ind)%metadata%varname)),
     &              ' as ',marbl_instance%interior_tendency_forcings(ind)%field_1d(1,nz)
            end if                     
         end if
      end if                              
      end subroutine if_test_print
      
      end module marbl_driver
#endif

!     MOM6 MARBL_tracers comments:
!! subroutinoe configure_MARBL_tracers(GV, param_file, CS)      
!     (1) Read all relevant parameters and write them to the model log.
      
!     (2) Read marbl settings file and call put_setting()
!       (2a) only master task opens file
!       (2b) master task reads file and broadcasts line-by-line
!          i. Read next line on master, iostat value out
!          (Exit loop if read is not successful; either read error or end of file)
!          ii. Broadcast line just read in on root PE to all tasks
!          iii. All tasks call put_setting (TODO: openMP blocks?)
!          iv. (TEMPORARY) don't set tracer restoring
!       (2c) we should always reach the EOF to capture the entire file...
      
!     (3) call marbl%init()
!     (4) Request fields needed by MOM6
!     (5) Initialize forcing fields
!       i. store all surface forcing indices
!      ii. store all interior forcing indices      
      
!! subroutine initialize_MARBL_tracers(restart, day, G, GV, US, h, param_file, diag, OBC, CS, sponge_CSp)
!! subroutine register_MARBL_diags(MARBL_diags, diag, day, G, id_diags)
!! subroutine setup_saved_state(MARBL_saved_state, HI, GV, restart_CS, tracers_may_reinit, local_saved_state)
!! subroutine MARBL_tracers_column_physics(h_old, h_new, ea, eb, fluxes, dt, G, GV, US, CS, tv, &
!     (1) Compute surface fluxes
!     (2) Post surface fluxes and their diagnostics (currently all 2D)
!     (3) Apply surface fluxes via vertical diffusion
!     (4) Compute interior tendencies
!     i.   only want ocean points in this loop
!     ii.  Set up vertical domain and bot_flux_to_tend
!     iii. Load proper column data
!     iv. Compute interior tendencies in MARBL <<<<<!!!!!!!!!!!!!!!!!!!!!!!!
!     v. Apply tendencies immediately
!     vi. Copy output that MOM6 needs to hold on to      
