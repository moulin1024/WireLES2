!###############################################################################
! sgs: compute sgs stresses with lasd from ref.
!###############################################################################
! ref : Bou-Zeid et al. A scale-dependent Lagrangian dynamic model for
! large eddy simulation of complex turbulent flows. Physics of fluids. 2005
!###############################################################################
! 1. sgs (call cs)
! 2. cs (call lagrng)
! 3. lagrng
!###############################################################################

!===============================================================================
! 1. sgs_stag
!===============================================================================
module sgs_cpu_m
    use precision
    use dimen
    use update_m
    use filter_cpu_m
    contains
subroutine sgs_cpu(txx,txy,txz,tyy,tyz,tzz,cs2,beta,&
    u,v,w,dudx,dudy,dudz,dvdx,dvdy,dvdz,dwdx,dwdy,dwdz, &
    lm_old,mm_old,qn_old,nn_old,t,me,nall)

    !---------------------------------------------------------------------------
    ! declaration
    !---------------------------------------------------------------------------
    use dimen
    implicit none

    real(fp),dimension(nx,ny,nz2),intent(out) :: txx,txy,tyy,tzz,beta
    real(fp),dimension(nx,ny,nz2),intent(inout) :: txz,tyz,cs2
    real(fp),dimension(nx,ny,nz2),intent(in) :: u,v,w,dudx,dudy,dudz,dvdx,dvdy,dvdz,dwdx,dwdy,dwdz
    real(fp),dimension(nx,ny,nz2),intent(inout) :: lm_old,mm_old,qn_old,nn_old
    integer*4,intent(in) :: t,me,nall

    real(fp),dimension(nx,ny,nz2) :: w_,u_lag,v_lag,w_lag,s,s11,s12,s13,s22,s23,s33
    real(fp),dimension(nx,ny):: txzp,tyzp
    real(fp) :: factor
    integer :: i,j,k

    save u_lag,v_lag,w_lag

    !---------------------------------------------------------------------------
    ! init for t=0
    !---------------------------------------------------------------------------

    ! this could be improved (damped smag)
    if (t == 1 .and. resub_flag == 0 .and. sim_flag < 2) then
        do k=2,nzb+1
            do j=1,ny
                do i=1,nx
                    cs2(i,j,k)=co**2.
                end do
            end do
        end do
        call update_uv_cpu(cs2,me,nall)
    end if

    if (t == 1) then
        u_lag = 0._fp
        v_lag = 0._fp
        w_lag = 0._fp
    end if

    !---------------------------------------------------------------------------
    ! prepare data (at uv nodes)
    !---------------------------------------------------------------------------

    do k = 2, nzb+1
        do j = 1, ny
            do i = 1, nx
                w_(i,j,k) = 0.5_fp*(w(i,j,k)+w(i,j,k+1))
                s11(i,j,k) = dudx(i,j,k)
                s22(i,j,k) = dvdy(i,j,k)
                s33(i,j,k) = dwdz(i,j,k)
                s12(i,j,k) = 0.5_fp*(dudy(i,j,k)+dvdx(i,j,k))
                s13(i,j,k) = 0.25_fp*(dudz(i,j,k)+dudz(i,j,k+1))+0.25_fp*(dwdx(i,j,k)+dwdx(i,j,k+1))
                s23(i,j,k) = 0.25_fp*(dvdz(i,j,k)+dvdz(i,j,k+1))+0.25_fp*(dwdy(i,j,k)+dwdy(i,j,k+1))
            end do
        end do
    end do

    if (me == 0) then

        ! at bottom (me=0,k=2) txz,tyz are already computed thus, it needs to
        ! be saved and restored (check wall routine).

        do j=1,ny
            do i=1,nx
                txzp(i,j)=txz(i,j,2)
                tyzp(i,j)=tyz(i,j,2)
            end do
        end do

        ! at bottom (me=0,k=2) dudz,dvdz are computed at uv layer
        ! (check wall routine).

        do j = 1, ny
            do i = 1, nx
                s13(i,j,2) = 0.5_fp*dudz(i,j,2)+0.25_fp*(dwdx(i,j,2)+dwdx(i,j,3))
                s23(i,j,2) = 0.5_fp*dvdz(i,j,2)+0.25_fp*(dwdy(i,j,2)+dwdy(i,j,3))
            end do
        end do

    end if

    do k = 2, nzb+1
        do j = 1, ny
            do i = 1, nx
               s(i,j,k) = dsqrt(2._fp*(s11(i,j,k)**2._fp+s22(i,j,k)**2._fp+s33(i,j,k)**2._fp+ &
                  2._fp*(s12(i,j,k)**2._fp+s13(i,j,k)**2._fp+s23(i,j,k)**2._fp)))
            end do
        end do
    end do

    !---------------------------------------------------------------------------
    ! compute cs2 (at uv nodes)
    !---------------------------------------------------------------------------

    do k = 2, nzb+1
        do j = 1, ny
            do i = 1, nx
                u_lag(i,j,k)=u_lag(i,j,k)+u(i,j,k)/cs_count
                v_lag(i,j,k)=v_lag(i,j,k)+v(i,j,k)/cs_count
                w_lag(i,j,k)=w_lag(i,j,k)+w_(i,j,k)/cs_count
            end do
        end do
    end do

    if (mod(t-1,cs_count) == 0 .and. t /= 1) then

        call cs_cpu(Cs2,beta,u,v,w_,u_lag,v_lag,w_lag,s,S11,S12,S13,S22,S23,S33, &
            LM_old,MM_old,QN_old,NN_old,t,me,nall)

        call update_uv_cpu(cs2,me,nall)

        u_lag = 0._fp
        v_lag = 0._fp
        w_lag = 0._fp

    end if

    !---------------------------------------------------------------------------
    ! get tau
    !---------------------------------------------------------------------------

    !---------------------------------------------------------------------------
    ! get txx,tyy,tzz,txy (uv nodes)

    ! for molecular visco: factor = factor -2*nu/(u_scale*z_i)
    do k = 2, nzb+1
        do j = 1, ny
            do i = 1, nx
               factor = -2._fp*cs2(i,j,k)*delta**2._fp*s(i,j,k)

               txx(i,j,k) = factor*s11(i,j,k)
               tyy(i,j,k) = factor*s22(i,j,k)
               tzz(i,j,k) = factor*s33(i,j,k)
               txy(i,j,k) = factor*s12(i,j,k)

            end do
        end do
    end do

    ! print *,txx(10,10,10)

    !---------------------------------------------------------------------------
    ! get txz,tyz (w nodes), here we recompute strain and interpolate cs,
    ! because cs is smooth but strain is not

    do k = 2, nzb+1
        do j = 1, ny
            do i = 1, nx
               s11(i,j,k) = 0.5_fp*(dudx(i,j,k-1)+dudx(i,j,k))
               s22(i,j,k) = 0.5_fp*(dvdy(i,j,k-1)+dvdy(i,j,k))
               s33(i,j,k) = 0.5_fp*(dwdz(i,j,k-1)+dwdz(i,j,k))
               s12(i,j,k) = 0.25_fp*(dudy(i,j,k-1)+dudy(i,j,k))+0.25_fp*(dvdx(i,j,k-1)+dvdx(i,j,k))
               s13(i,j,k) = 0.5_fp*(dudz(i,j,k)+dwdx(i,j,k))
               s23(i,j,k) = 0.5_fp*(dvdz(i,j,k)+dwdy(i,j,k))
               s(i,j,k)=dsqrt(2._fp*(s11(i,j,k)**2._fp+s22(i,j,k)**2._fp+s33(i,j,k)**2._fp+ &
                  2._fp*(s12(i,j,k)**2._fp+s13(i,j,k)**2._fp+s23(i,j,k)**2._fp)))
            end do
        end do
    end do

    ! for molecular visco: factor = factor -2*nu/(u_scale*z_i)
    do k = 2, nzb+1
        do j = 1, ny
            do i = 1, nx
               factor = -(cs2(i,j,k)+cs2(i,j,k-1))*delta**2._fp*s(i,j,k)
               txz(i,j,k) = factor*s13(i,j,k)
               tyz(i,j,k) = factor*s23(i,j,k)
            end do
        end do
    end do

    !---------------------------------------------------------------------------
    ! enforce bc
    !---------------------------------------------------------------------------

    if (me==0) then
        do j=1,ny
            do i=1,nx
                txz(i,j,2)=txzp(i,j)
                tyz(i,j,2)=tyzp(i,j)
            end do
        end do
    end if

    if (me==nprocs-1) then
        do j=1,ny
            do i=1,nx
                txz(i,j,nzb+1)=0._fp
                tyz(i,j,nzb+1)=0._fp
            end do
        end do
    end if

end subroutine sgs_cpu

!===============================================================================
! 2. optim_sd
!===============================================================================

subroutine cs_cpu(Cs2,beta,u,v,w_,u_lag,v_lag,w_lag,s,S11,S12,S13,S22,S23,S33, &
    LM_old,MM_old,QN_old,NN_old,t,me,nall)

    !---------------------------------------------------------------------------
    ! declaration
    !---------------------------------------------------------------------------
    use dimen
    implicit none

    real(fp),dimension(nx,ny,nz2),intent(out) :: Cs2,beta
    real(fp),dimension(nx,ny,nz2),intent(in) :: u,v,w_,u_lag,v_lag,w_lag,s,S11,S12,S13,S22,S23,S33
    real(fp),dimension(nx,ny,nz2),intent(inout) :: LM_old,MM_old,QN_old,NN_old
    integer*4,intent(in) :: t,me,nall

    real(fp),dimension(nx,ny,nz2) :: S_hat,S11_hat,S22_hat,S33_hat, &
        S12_hat,S13_hat,S23_hat,u_hat,v_hat,w_hat,uu_hat,uv_hat, &
        uw_hat,vv_hat,vw_hat,ww_hat,S_hatd,S11_hatd,S22_hatd, &
        S33_hatd,S12_hatd,S13_hatd,S23_hatd,u_hatd,v_hatd,w_hatd, &
        uu_hatd,uv_hatd,uw_hatd,vv_hatd,vw_hatd,ww_hatd,&
        SS11_hat,SS12_hat,SS13_hat,SS22_hat,SS23_hat,SS33_hat, &
        SS11_hatd,SS12_hatd,SS13_hatd,SS22_hatd,SS23_hatd,SS33_hatd, &
        uu,uv,uw,vv,vw,ww,SS11,SS22,SS33,SS12,SS13,SS23

    real(fp),dimension(nx,ny,nz2) :: LM,MM,QN,NN

    real(fp) :: L11,L12,L13,L22,L23,L33,M11,M12,M13,M22,M23,M33,Cs2_2d,Cs2_4d

    integer :: i,j,k,kend

    real(fp), parameter :: const = 2._fp*(delta**2)
    real(fp), parameter :: tf1=tfr
    real(fp), parameter :: tf2=tfr*tfr
    real(fp), parameter :: tf1_2=tf1**2
    real(fp), parameter :: tf2_2=tf2**2
    real(fp), parameter :: beta_min = 1._fp/(tf1*tf2)
    ! real(fp), parameter :: beta_max = 1.5_fp ! clipping is needed for ta_beta
    real(fp), parameter :: cs2_min = 0.001_fp*0.001_fp
    real(fp), parameter :: cs2_max = 0.9_fp*0.9_fp

    !---------------------------------------------------------------------------
    ! main code
    !---------------------------------------------------------------------------
    ! note: if we remove 3d lagr av then everything can be done in one slab...

    !---------------------------------------------------------------------------
    ! prepare data --> this all part could be done in slabs

    do k=2,Nzb+1
      do j=1,Ny
        do i=1,Nx

          SS11(i,j,k)=S(i,j,k)*S11(i,j,k)
          SS33(i,j,k)=S(i,j,k)*S33(i,j,k)
          SS22(i,j,k)=S(i,j,k)*S22(i,j,k)
          SS12(i,j,k)=S(i,j,k)*S12(i,j,k)
          SS13(i,j,k)=S(i,j,k)*S13(i,j,k)
          SS23(i,j,k)=S(i,j,k)*S23(i,j,k)

          uu(i,j,k)=u(i,j,k)**2._fp
          vv(i,j,k)=v(i,j,k)**2._fp
          ww(i,j,k)=w_(i,j,k)**2._fp
          uv(i,j,k)=u(i,j,k)*v(i,j,k)
          vw(i,j,k)=v(i,j,k)*w_(i,j,k)
          uw(i,j,k)=u(i,j,k)*w_(i,j,k)

        enddo
      enddo
    enddo

    Call filter_sgs_cpu(u_hat,u_hatd,u,1)
    Call filter_sgs_cpu(v_hat,v_hatd,v,1)
    Call filter_sgs_cpu(w_hat,w_hatd,w_,1)
    Call filter_sgs_cpu(uu_hat,uu_hatd,uu,1)
    Call filter_sgs_cpu(vv_hat,vv_hatd,vv,1)
    Call filter_sgs_cpu(ww_hat,ww_hatd,ww,1)
    Call filter_sgs_cpu(uv_hat,uv_hatd,uv,1)
    Call filter_sgs_cpu(uw_hat,uw_hatd,uw,1)
    Call filter_sgs_cpu(vw_hat,vw_hatd,vw,1)
    Call filter_sgs_cpu(S11_hat,S11_hatd,S11,1)
    Call filter_sgs_cpu(S22_hat,S22_hatd,S22,1)
    Call filter_sgs_cpu(S33_hat,S33_hatd,S33,1)
    Call filter_sgs_cpu(S12_hat,S12_hatd,S12,1)
    Call filter_sgs_cpu(S13_hat,S13_hatd,S13,1)
    Call filter_sgs_cpu(S23_hat,S23_hatd,S23,1)
    Call filter_sgs_cpu(SS11_hat,SS11_hatd,SS11,1)
    Call filter_sgs_cpu(SS22_hat,SS22_hatd,SS22,1)
    Call filter_sgs_cpu(SS33_hat,SS33_hatd,SS33,1)
    Call filter_sgs_cpu(SS12_hat,SS12_hatd,SS12,1)
    Call filter_sgs_cpu(SS13_hat,SS13_hatd,SS13,1)
    Call filter_sgs_cpu(SS23_hat,SS23_hatd,SS23,1)

    do k=2,nzb+1
        do j=1,ny
            do i=1,nx

                S_hat(i,j,k)=sqrt(2._fp*(S11_hat(i,j,k)**2._fp+ &
                    S22_hat(i,j,k)**2._fp+S33_hat(i,j,k)**2._fp+ &
                    2._fp*S12_hat(i,j,k)**2._fp+2._fp*S13_hat(i,j,k)**2._fp+ &
                    2._fp*S23_hat(i,j,k)**2._fp))
                S_hatd(i,j,k)=sqrt(2._fp*(S11_hatd(i,j,k)**2._fp+ &
                    S22_hatd(i,j,k)**2._fp+S33_hatd(i,j,k)**2._fp+ &
                    2._fp*S12_hatd(i,j,k)**2._fp+2._fp*S13_hatd(i,j,k)**2._fp+ &
                    2._fp*S23_hatd(i,j,k)**2._fp))

            enddo
        enddo
    enddo

    do k=2,Nzb+1
        do j=1,ny
            do i=1,nx
                ! Lij
                L11=(uu_hat(i,j,k))-(u_hat(i,j,k))**2._fp
                L22=(vv_hat(i,j,k))-(v_hat(i,j,k))**2._fp
                L12=(uv_hat(i,j,k))-(u_hat(i,j,k)*v_hat(i,j,k))
                L13=(uw_hat(i,j,k))-(u_hat(i,j,k)*w_hat(i,j,k))
                L23=(vw_hat(i,j,k))-(v_hat(i,j,k)*w_hat(i,j,k))
                L33=(ww_hat(i,j,k))-(w_hat(i,j,k))**2._fp
                ! Mij
                M11=const*(SS11_hat(i,j,k)-tf1_2*S_hat(i,j,k)*S11_hat(i,j,k))
                M12=const*(SS12_hat(i,j,k)-tf1_2*S_hat(i,j,k)*S12_hat(i,j,k))
                M13=const*(SS13_hat(i,j,k)-tf1_2*S_hat(i,j,k)*S13_hat(i,j,k))
                M22=const*(SS22_hat(i,j,k)-tf1_2*S_hat(i,j,k)*S22_hat(i,j,k))
                M23=const*(SS23_hat(i,j,k)-tf1_2*S_hat(i,j,k)*S23_hat(i,j,k))
                M33=const*(SS33_hat(i,j,k)-tf1_2*S_hat(i,j,k)*S33_hat(i,j,k))
                ! LM and MM
                LM(i,j,k)=L11*M11+L22*M22+L33*M33+2._fp*(L12*M12+L13*M13+L23*M23)
                MM(i,j,k)=M11**2._fp+M22**2._fp+M33**2._fp+2._fp*(M12**2._fp+M13**2._fp+M23**2._fp)
                ! Qij (re-use Lij)
                L11=(uu_hatd(i,j,k))-(u_hatd(i,j,k))**2._fp
                L22=(vv_hatd(i,j,k))-(v_hatd(i,j,k))**2._fp
                L12=(uv_hatd(i,j,k))-(u_hatd(i,j,k)*v_hatd(i,j,k))
                L13=(uw_hatd(i,j,k))-(u_hatd(i,j,k)*w_hatd(i,j,k))
                L23=(vw_hatd(i,j,k))-(v_hatd(i,j,k)*w_hatd(i,j,k))
                L33=(ww_hatd(i,j,k))-(w_hatd(i,j,k))**2._fp
                ! Nij (re-use Nij)
                M11=const*(SS11_hatd(i,j,k)-tf2_2*S_hatd(i,j,k)*S11_hatd(i,j,k))
                M12=const*(SS12_hatd(i,j,k)-tf2_2*S_hatd(i,j,k)*S12_hatd(i,j,k))
                M13=const*(SS13_hatd(i,j,k)-tf2_2*S_hatd(i,j,k)*S13_hatd(i,j,k))
                M22=const*(SS22_hatd(i,j,k)-tf2_2*S_hatd(i,j,k)*S22_hatd(i,j,k))
                M23=const*(SS23_hatd(i,j,k)-tf2_2*S_hatd(i,j,k)*S23_hatd(i,j,k))
                M33=const*(SS33_hatd(i,j,k)-tf2_2*S_hatd(i,j,k)*S33_hatd(i,j,k))
                ! QN and NN
                QN(i,j,k)=L11*M11+L22*M22+L33*M33+2._fp*(L12*M12+L13*M13+L23*M23)
                NN(i,j,k)=M11**2._fp+M22**2._fp+M33**2._fp+2._fp*(M12**2._fp+M13**2._fp+M23**2._fp)
            enddo
        enddo
    enddo
    
    !---------------------------------------------------------------------------
    ! init, update and bc of old variables
    if (t.eq.cs_count .and. resub_flag == 0 .and. sim_flag < 2) then
        do k=2,Nzb+1
            do j=1,ny
                do i=1,nx
                    LM_old(i,j,k)=0.03_fp*MM(i,j,k)
                    MM_old(i,j,k)=MM(i,j,k)
                    QN_old(i,j,k)=0.03_fp*NN(i,j,k)
                    NN_old(i,j,k)=NN(i,j,k)
                enddo
            enddo
        enddo
    end if

    ! must be updated top and bot for intep3d
    call update_cpu(LM_old,me,nall)
    call update_cpu(MM_old,me,nall)
    call update_cpu(QN_old,me,nall)
    call update_cpu(NN_old,me,nall)

    
    if (me==0) then
        do j=1,ny
            do i=1,nx
                LM_old(i,j,1)=LM_old(i,j,2)
                MM_old(i,j,1)=MM_old(i,j,2)
                QN_old(i,j,1)=QN_old(i,j,2)
                NN_old(i,j,1)=NN_old(i,j,2)
            end do
        end do
    end if

    if (me==nprocs-1) then
        do j=1,ny
            do i=1,nx
                LM_old(i,j,nzb+1)=LM_old(i,j,nzb)
                MM_old(i,j,nzb+1)=MM_old(i,j,nzb)
                QN_old(i,j,nzb+1)=QN_old(i,j,nzb)
                NN_old(i,j,nzb+1)=NN_old(i,j,nzb)
            end do
        end do
    end if

    !---------------------------------------------------------------------------
    ! compute lagr av and cs

    do k=2,nzb+1
        do j=1,ny
            do i=1,nx

                call lagrng_cpu(lm(i,j,k),mm(i,j,k),qn(i,j,k),nn(i,j,k), &
                    lm_old,mm_old,qn_old,nn_old, &
                    u_lag(i,j,k),v_lag(i,j,k),w_lag(i,j,k),&
                    i,j,k)

                ! get Cs2_2d
                Cs2_2d = LM(i,j,k)/MM(i,j,k)
                Cs2_2d = max(0.0_fp,Cs2_2d)

                ! get Cs2_4d
                Cs2_4d = QN(i,j,k)/NN(i,j,k)
                Cs2_4d = max(0.0_fp,Cs2_4d)

                ! get beta
                Beta(i,j,k) = (Cs2_4d/Cs2_2d)**(log(tf1)/(log(tf2)-log(tf1)))
                Beta(i,j,k) = max(Beta(i,j,k),beta_min)
                ! Beta(i,j,k) = min(Beta(i,j,k),beta_max)

                ! get Cs2
                Cs2(i,j,k)=Cs2_2d/Beta(i,j,k)
                Cs2(i,j,k)=max(Cs2(i,j,k),cs2_min)
                Cs2(i,j,k)=min(Cs2(i,j,k),cs2_max)
                
            enddo
        enddo
    enddo

    !---------------------------------------------------------------------------
    ! save old var

    do k=2,nzb+1
        do j=1,ny
            do i=1,nx
                LM_old(i,j,k)=LM(i,j,k)
                MM_old(i,j,k)=MM(i,j,k)
                QN_old(i,j,k)=QN(i,j,k)
                NN_old(i,j,k)=NN(i,j,k)
            enddo
        enddo
    enddo

end subroutine cs_cpu

!===============================================================================
! 3. lagrng
!===============================================================================

subroutine lagrng_cpu(lm,mm,qn,nn,lm_old,mm_old,qn_old,nn_old,u_lag,v_lag,w_lag,i,j,k)

    !---------------------------------------------------------------------------
    ! declaration
    !---------------------------------------------------------------------------
    use dimen
    implicit none

    real(fp),intent(inout) :: lm,mm,qn,nn
    real(fp),dimension(nx,ny,nz2),intent(in) :: lm_old,mm_old,qn_old,nn_old
    real(fp),intent(in) :: u_lag,v_lag,w_lag
    integer,intent(in) :: i,j,k

    real(fp) :: xi,yi,zi,iw,jw,kw,lmi,mmi,qni,nni,eps,tn
    integer :: ii,jj,kk,iplus,jplus

    !---------------------------------------------------------------------------
    ! compute lagrangian interpolation
    !---------------------------------------------------------------------------

    !---------------------------------------------------------------------------
    ! location of interp

    xi=-u_lag*dtl
    yi=-v_lag*dtl
    zi=-w_lag*dtl

    !---------------------------------------------------------------------------
    ! get iw,ii,iplus

    if (xi<0._fp) then
        iw=(dx+xi)/dx
        if (i==1) then
            ii=nx
        else
            ii=i-1
        endif
    else
        iw=(xi)/dx
        ii=i
    endif

    if (ii==nx) then
        iplus=-nx+1
    else
        iplus=1
    endif

    !---------------------------------------------------------------------------
    ! get jw,jj,jplus

    if (yi<0._fp) then
        jw=(dy+yi)/dy
        if (j==1) then
            jj=ny
        else
            jj=j-1
        endif
    else
        jw=(yi)/dy
        jj=j
    endif

    if (jj==ny) then
        jplus=-ny+1
    else
        jplus=1
    endif

    !---------------------------------------------------------------------------
    ! get kw,kk

    if (zi<0.0) then
        kw=(dz+zi)/dz
        kk=k-1
    else
        kw=(zi)/dz
        kk=k
    endif

    !---------------------------------------------------------------------------
    ! compute lmi,mmi,qni,nni

    lmi = lm_old(ii,jj,kk)*(1._fp-iw)*(1._fp-jw)*(1._fp-kw)+ &
        lm_old(ii+iplus,jj,kk)*iw*(1._fp-jw)*(1._fp-kw)+ &
        lm_old(ii+iplus,jj+jplus,kk)*iw*jw*(1._fp-kw)+ &
        lm_old(ii,jj+jplus,kk)*(1._fp-iw)*jw*(1._fp-kw)+ &
        lm_old(ii,jj,kk+1)*(1._fp-iw)*(1._fp-jw)*kw+ &
        lm_old(ii+iplus,jj,kk+1)*iw*(1._fp-jw)*kw+ &
        lm_old(ii+iplus,jj+jplus,kk+1)*iw*jw*kw+ &
        lm_old(ii,jj+jplus,kk+1)*(1._fp-iw)*jw*kw

    mmi = mm_old(ii,jj,kk)*(1._fp-iw)*(1._fp-jw)*(1._fp-kw)+ &
        mm_old(ii+iplus,jj,kk)*iw*(1._fp-jw)*(1._fp-kw)+ &
        mm_old(ii+iplus,jj+jplus,kk)*iw*jw*(1._fp-kw)+ &
        mm_old(ii,jj+jplus,kk)*(1._fp-iw)*jw*(1._fp-kw)+ &
        mm_old(ii,jj,kk+1)*(1._fp-iw)*(1._fp-jw)*kw+ &
        mm_old(ii+iplus,jj,kk+1)*iw*(1._fp-jw)*kw+ &
        mm_old(ii+iplus,jj+jplus,kk+1)*iw*jw*kw+ &
        mm_old(ii,jj+jplus,kk+1)*(1._fp-iw)*jw*kw

    qni = qn_old(ii,jj,kk)*(1._fp-iw)*(1._fp-jw)*(1._fp-kw)+ &
        qn_old(ii+iplus,jj,kk)*iw*(1._fp-jw)*(1._fp-kw)+ &
        qn_old(ii+iplus,jj+jplus,kk)*iw*jw*(1._fp-kw)+ &
        qn_old(ii,jj+jplus,kk)*(1._fp-iw)*jw*(1._fp-kw)+ &
        qn_old(ii,jj,kk+1)*(1._fp-iw)*(1._fp-jw)*kw+ &
        qn_old(ii+iplus,jj,kk+1)*iw*(1._fp-jw)*kw+ &
        qn_old(ii+iplus,jj+jplus,kk+1)*iw*jw*kw+ &
        qn_old(ii,jj+jplus,kk+1)*(1._fp-iw)*jw*kw

    nni = nn_old(ii,jj,kk)*(1._fp-iw)*(1._fp-jw)*(1._fp-kw)+ &
        nn_old(ii+iplus,jj,kk)*iw*(1._fp-jw)*(1._fp-kw)+ &
        nn_old(ii+iplus,jj+jplus,kk)*iw*jw*(1._fp-kw)+ &
        nn_old(ii,jj+jplus,kk)*(1._fp-iw)*jw*(1._fp-kw)+ &
        nn_old(ii,jj,kk+1)*(1._fp-iw)*(1._fp-jw)*kw+ &
        nn_old(ii+iplus,jj,kk+1)*iw*(1._fp-jw)*kw+ &
        nn_old(ii+iplus,jj+jplus,kk+1)*iw*jw*kw+ &
        nn_old(ii,jj+jplus,kk+1)*(1._fp-iw)*jw*kw

    !---------------------------------------------------------------------------
    ! compute lagrangian averaged values
    !---------------------------------------------------------------------------

    !---------------------------------------------------------------------------
    ! lm and mm

    tn = max(lm_old(i,j,k)*mm_old(i,j,k),0.0_fp)
    tn = 1.5_fp*delta*tn**(-1._fp/8._fp)
    tn = max(0.0_fp, tn)
    eps=(dtl/tn)/(1._fp+dtl/tn)

    lm=eps*lm+(1._fp-eps)*lmi
    mm=eps*mm+(1._fp-eps)*mmi

    !---------------------------------------------------------------------------
    ! qn and nn

    tn = max(qn_old(i,j,k)*nn_old(i,j,k),0.0_fp)
    tn = 1.5_fp*delta*tn**(-1._fp/8._fp)
    tn = max(0.0_fp, tn)
    eps=(dtl/tn)/(1._fp+dtl/tn)

    qn=eps*qn+(1._fp-eps)*qni
    nn=eps*nn+(1._fp-eps)*nni
end subroutine lagrng_cpu

end module sgs_cpu_m