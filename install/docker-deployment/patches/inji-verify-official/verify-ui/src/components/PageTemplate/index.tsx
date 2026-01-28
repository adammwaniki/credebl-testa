import React from 'react';
import Navbar from "./Navbar";
import Copyrights from "./Copyrights";
import CheckingForInternetConnectivity from "../misc/CheckingForInternetConnectivity";
import Header from '../Home/Header';
import {Outlet} from "react-router-dom";
import { OfflineSyncPanel } from '../OfflineSync';

const PageTemplate = (props: any) => {
    return (
        <div>
            <Navbar/>
            <div className="w-full bg-pageBackGroundColor text-center">
                <Header/>
            </div>
            <Outlet/>
            <Copyrights/>
            <CheckingForInternetConnectivity/>
            <OfflineSyncPanel/>
        </div>
    );
}

export default PageTemplate;
